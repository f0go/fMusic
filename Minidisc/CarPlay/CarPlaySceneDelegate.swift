import CarPlay
import SwiftSonic

/// CarPlay may launch without a phone scene. Always use the shared runtime.
@MainActor
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate, CPTabBarTemplateDelegate {
    private var controller: CPInterfaceController?
    private var loads: [ObjectIdentifier: Task<Void, Never>] = [:]

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        interfaceController.delegate = self
        let root = makeRootTemplate()
        root.delegate = self
        interfaceController.setRootTemplate(root, animated: false, completion: nil)
        if let first = root.templates.first { reload(first) }
    }

    func makeRootTemplate() -> CPTabBarTemplate {
        let songs = list(String(localized: "Songs"), icon: "music.note.list")
        let albums = list(String(localized: "Albums"), icon: "square.stack")
        let playlists = list(String(localized: "Playlists"), icon: "music.note.list")
        songs.userInfo = "songs"
        albums.userInfo = "albums"
        playlists.userInfo = "playlists"
        return CPTabBarTemplate(templates: [songs, albums, playlists])
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        loads.values.forEach { $0.cancel() }
        loads.removeAll()
        interfaceController.delegate = nil
        controller = nil
    }

    func templateWillAppear(_ template: CPTemplate, animated: Bool) {
        reload((template as? CPTabBarTemplate)?.selectedTemplate ?? template)
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        reload(selectedTemplate)
    }

    private func reload(_ template: CPTemplate) {
        guard let list = template as? CPListTemplate, let kind = list.userInfo as? String else { return }
        load(list, kind: kind)
    }

    private func list(_ title: String, icon: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: icon)
        template.emptyViewTitleVariants = [String(localized: "Loading…")]
        return template
    }

    private func load(_ template: CPListTemplate, kind: String) {
        let id = ObjectIdentifier(template)
        loads[id]?.cancel()
        loads[id] = Task { [weak self, weak template] in
            guard let self, let template else { return }
            defer { if !Task.isCancelled { self.loads[id] = nil } }
            do {
                let container = try await MinidiscRuntime.shared.container()
                let version = container.serverState.activeConnectionVersion
                let serverID = container.serverState.activeServer?.id
                await container.offlineLibrary.refresh()
                let offline = container.offlineLibrary.snapshot
                let local = container.localMusic.catalog
                let online = container.serverState.isOnline && serverID != nil
                var items: [CPListItem] = []
                switch kind {
                case "songs":
                    let remote = online ? try await container.libraryService.allSongs(offset: 0, count: CPListTemplate.maximumItemCount).map { DisplayableSong(from: $0) } : offline.songs
                    items = songItems(local.playable(local.songs) + remote, container: container)
                case "albums":
                    let remote = online ? try await container.libraryService.recentlyAddedAlbums(size: CPListTemplate.maximumItemCount) : offline.albums
                    items = (local.albums + remote).prefix(CPListTemplate.maximumItemCount).map { album in
                        let item = CPListItem(text: album.name, detailText: album.artist)
                        item.accessoryType = .disclosureIndicator
                        item.handler = { [weak self] _, completion in
                            guard container.serverState.activeServer?.id == serverID,
                                  container.serverState.activeConnectionVersion == version else { completion(); return }
                            self?.showSongs(title: album.name, container: container) {
                                if let group = local.groups[album.id] { return local.playable(group.tracks.map(\.song)) }
                                if !container.serverState.isOnline { return container.offlineLibrary.snapshot.albumSongs(album.id) }
                                return try await container.libraryService.album(id: album.id).song?.map { DisplayableSong(from: $0) } ?? []
                            }
                            completion()
                        }
                        return item
                    }
                default:
                    let playlists = online ? try await container.libraryService.playlists() : offline.playlists
                    items = playlists.prefix(CPListTemplate.maximumItemCount).map { playlist in
                        let item = CPListItem(text: playlist.name, detailText: nil)
                        item.accessoryType = .disclosureIndicator
                        item.handler = { [weak self] _, completion in
                            guard container.serverState.activeServer?.id == serverID,
                                  container.serverState.activeConnectionVersion == version else { completion(); return }
                            self?.showSongs(title: playlist.name, container: container) {
                                if !container.serverState.isOnline { return container.offlineLibrary.snapshot.playlistSongs[playlist.id] ?? [] }
                                return try await container.libraryService.playlist(id: playlist.id).entry?.map { DisplayableSong(from: $0) } ?? []
                            }
                            completion()
                        }
                        return item
                    }
                }
                try Task.checkCancellation()
                guard self.controller != nil, container.serverState.activeServer?.id == serverID,
                      container.serverState.activeConnectionVersion == version else { return }
                template.emptyViewTitleVariants = [String(localized: "No Results")]
                template.updateSections([CPListSection(items: items)])
            } catch is CancellationError {
            } catch {
                showError(on: template) { [weak self, weak template] in
                    guard let template else { return }
                    self?.load(template, kind: kind)
                }
            }
        }
    }

    private func showSongs(title: String, container: AppContainer,
                           fetch: @escaping @MainActor () async throws -> [DisplayableSong]) {
        guard let controller else { return }
        let template = list(title, icon: "music.note")
        controller.pushTemplate(template, animated: true, completion: nil)
        let id = ObjectIdentifier(template)
        loads[id] = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.loads[id] = nil } }
            let serverID = container.serverState.activeServer?.id
            let version = container.serverState.activeConnectionVersion
            do {
                let songs = try await fetch()
                try Task.checkCancellation()
                guard self.controller != nil, container.serverState.activeServer?.id == serverID,
                      container.serverState.activeConnectionVersion == version else { return }
                template.emptyViewTitleVariants = [String(localized: "No Songs")]
                template.updateSections([CPListSection(items: songItems(songs, container: container))])
            } catch is CancellationError {
            } catch {
                showError(on: template) { [weak self] in
                    self?.controller?.popTemplate(animated: true, completion: nil)
                }
            }
        }
    }

    private func songItems(_ songs: [DisplayableSong], container: AppContainer) -> [CPListItem] {
        let queue = Array(songs.prefix(CPListTemplate.maximumItemCount))
        let serverID = container.serverState.activeServer?.id
        let version = container.serverState.activeConnectionVersion
        return queue.enumerated().map { index, song in
            let item = CPListItem(text: song.title, detailText: song.artist)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    defer { completion() }
                    guard let self, let interface = self.controller,
                          container.serverState.activeServer?.id == serverID,
                          container.serverState.activeConnectionVersion == version else { return }
                    do {
                        try await container.playerService.play(tracks: queue, startIndex: index)
                        guard self.controller === interface else { return }
                        interface.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                    } catch {
                        guard self.controller === interface else { return }
                        let alert = CPAlertTemplate(titleVariants: [String(localized: "Unable to Load")], actions: [
                            CPAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
                                self?.controller?.dismissTemplate(animated: true, completion: nil)
                            }
                        ])
                        self.controller?.presentTemplate(alert, animated: true, completion: nil)
                    }
                }
            }
            return item
        }
    }

    private func showError(on template: CPListTemplate, retry: @escaping @MainActor () -> Void) {
        guard controller != nil, !Task.isCancelled else { return }
        let item = CPListItem(text: String(localized: "Unable to Load"), detailText: String(localized: "Retry"))
        item.handler = { _, completion in retry(); completion() }
        template.updateSections([CPListSection(items: [item])])
    }
}
