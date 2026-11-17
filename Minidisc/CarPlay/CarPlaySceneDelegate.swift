import CarPlay
import SwiftSonic

/// CarPlay may launch without a phone scene. Always use the shared runtime.
@MainActor
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var controller: CPInterfaceController?
    private var playbackControls: [ObjectIdentifier: CarPlayPlaybackControls] = [:]
    private var loads: [ObjectIdentifier: Task<Void, Never>] = [:]

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        interfaceController.delegate = self
        let root = makeRootTemplate()
        interfaceController.setRootTemplate(root, animated: false, completion: nil)
        reload(root)
    }

    func makeRootTemplate() -> CPListTemplate {
        let home = list(String(localized: "Home"), icon: "house")
        home.userInfo = "home"
        home.assistantCellConfiguration = CPAssistantCellConfiguration(
            position: .top, visibility: .always, assistantAction: .playMedia
        )
        home.leadingNavigationBarButtons = [CPBarButton(title: String(localized: "Library")) { [weak self] _ in
            self?.showLibrary()
        }]
        return home
    }

    private func showLibrary() {
        let template = list(String(localized: "Library"), icon: "music.note.house")
        let items = [(String(localized: "Albums"), "albums"), (String(localized: "Playlists"), "playlists")].map { title, kind in
            let item = CPListItem(text: title, detailText: nil)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                let destination = self.list(title, icon: "music.note.list")
                destination.userInfo = kind
                self.controller?.pushTemplate(destination, animated: true, completion: nil)
                completion()
            }
            return item
        }
        template.updateSections([CPListSection(items: items)])
        controller?.pushTemplate(template, animated: true, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        loads.values.forEach { $0.cancel() }
        loads.removeAll()
        playbackControls.values.forEach { $0.stop() }
        playbackControls.removeAll()
        interfaceController.delegate = nil
        controller = nil
    }

    func templateWillAppear(_ template: CPTemplate, animated: Bool) {
        reload(template)
    }

    func templateDidDisappear(_ template: CPTemplate, animated: Bool) {
        guard controller?.templates.contains(where: { $0 === template }) != true else { return }
        playbackControls.removeValue(forKey: ObjectIdentifier(template))?.stop()
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
                var sections: [CPListSection]?
                switch kind {
                case "home":
                    sections = await homeSections(container: container)
                case "songs":
                    let remote = online ? try await container.libraryService.allSongs(offset: 0, count: CPListTemplate.maximumItemCount).map { DisplayableSong(from: $0) } : offline.songs
                    items = songItems(local.playable(local.songs) + remote, container: container)
                case "albums":
                    let remote = online ? try await container.libraryService.recentlyAddedAlbums(size: CPListTemplate.maximumItemCount) : offline.albums
                    items = albumItems(local.albums + remote, container: container)
                default:
                    let playlists = online ? try await container.libraryService.playlists() : offline.playlists
                    items = playlistItems(playlists, container: container)
                }
                try Task.checkCancellation()
                guard self.controller != nil, container.serverState.activeServer?.id == serverID,
                      container.serverState.activeConnectionVersion == version else { return }
                template.emptyViewTitleVariants = [String(localized: "No Results")]
                template.updateSections(sections ?? [CPListSection(items: items)])
            } catch is CancellationError {
            } catch {
                showError(on: template) { [weak self, weak template] in
                    guard let template else { return }
                    self?.load(template, kind: kind)
                }
            }
        }
    }

    private func albumItems(_ albums: [AlbumID3], container: AppContainer) -> [CPListItem] {
        let serverID = container.serverState.activeServer?.id
        let version = container.serverState.activeConnectionVersion
        let local = container.localMusic.catalog
        return albums.prefix(CPListTemplate.maximumItemCount).map { album in
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
    }

    private func playlistItems(_ playlists: [Playlist], container: AppContainer) -> [CPListItem] {
        let serverID = container.serverState.activeServer?.id
        let version = container.serverState.activeConnectionVersion
        return playlists.prefix(CPListTemplate.maximumItemCount).map { playlist in
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

    private func playlistCarousel(_ playlists: [Playlist], title: String,
                                  container: AppContainer) async -> CPListImageRowItem {
        let visible = Array(playlists.prefix(MinidiscCarouselMetrics.previewLimit))
        let selections = playlistItems(visible, container: container)
        var elements: [CPListImageRowItemRowElement] = []
        for playlist in visible {
            let localID = await PlaylistCoverManager.localCoverId(
                playlistId: playlist.id, downloadService: container.downloadService)
            let image = await container.artworkImageCache.load(coverArtId: localID ?? playlist.coverArt ?? playlist.id)
            let artwork = image ?? Self.playlistPlaceholder()
            elements.append(CPListImageRowItemRowElement(image: artwork, title: playlist.name, subtitle: nil))
        }
        let row = CPListImageRowItem(text: title, elements: elements, allowsMultipleLines: false)
        row.listImageRowHandler = { _, index, completion in
            guard selections.indices.contains(index) else { completion(); return }
            let item = selections[index]
            item.handler?(item, completion)
        }
        row.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            let template = self.list(title, icon: "music.note.list")
            template.userInfo = "playlists"
            self.controller?.pushTemplate(template, animated: true, completion: nil)
            completion()
        }
        return row
    }

    private static func playlistPlaceholder() -> UIImage {
        let size = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.secondarySystemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIImage(systemName: "music.note.list")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 70, y: 70, width: 100, height: 100))
        }
    }

    private func homeSections(container: AppContainer) async -> [CPListSection] {
        var feed: HomeFeedViewModel?
        if let serverID = container.serverState.activeServer?.id {
            let model = HomeFeedViewModel(libraryService: container.libraryService,
                                         cache: HomeFeedCache.shared, serverID: serverID)
            await model.load(isOnline: container.serverState.isOnline)
            feed = model
        }
        let content = CarPlayHomeSection.content(feed: feed, container: container)
        var remaining = CPListTemplate.maximumItemCount
        var result: [CPListSection] = []
        for section in content.prefix(CPListTemplate.maximumSectionCount) {
            guard remaining > 0 else { break }
            let items: [CPListItem]
            switch section.content {
            case .songs:
                let favorites: [SwiftSonic.Song]
                if container.serverState.isOnline {
                    favorites = (try? await container.libraryService.getStarred2().song) ?? feed?.favorites.songs ?? []
                } else {
                    favorites = container.offlineLibrary.snapshot.favorites.songs
                }
                let ranked = CarPlayHomeSection.rankedFavorites(favorites).map { DisplayableSong(from: $0) }
                let header = CPListItem(text: section.title, detailText: nil)
                header.accessoryType = .disclosureIndicator
                let serverID = container.serverState.activeServer?.id
                let version = container.serverState.activeConnectionVersion
                header.handler = { [weak self] _, completion in
                    guard container.serverState.activeServer?.id == serverID,
                          container.serverState.activeConnectionVersion == version else { completion(); return }
                    self?.showSongs(title: section.title, container: container) { ranked }
                    completion()
                }
                let preview = songItems(Array(ranked.prefix(5)), container: container)
                let visible = Array(([header] + preview).prefix(remaining))
                remaining -= visible.count
                result.append(CPListSection(items: visible))
                continue
            case .albums(let albums): items = albumItems(albums, container: container)
            case .playlists(let playlists):
                let carousel = await playlistCarousel(playlists, title: section.title, container: container)
                remaining -= 1
                result.append(CPListSection(items: [carousel]))
                continue
            case .artists(let artists):
                let local = container.localMusic.catalog
                items = artists.map { artist in
                    let item = CPListItem(text: artist.name, detailText: nil)
                    item.accessoryType = .disclosureIndicator
                    item.handler = { [weak self] _, completion in
                        self?.showSongs(title: artist.name, container: container) {
                            guard let group = local.groups[artist.id] else { return [] }
                            return local.playable(group.tracks.map(\.song))
                        }
                        completion()
                    }
                    return item
                }
            }
            let visible = Array(items.prefix(remaining))
            remaining -= visible.count
            result.append(CPListSection(items: visible, header: section.title, sectionIndexTitle: nil))
        }
        return result
    }

    private func showSongs(title: String, container: AppContainer,
                           fetch: @escaping @MainActor () async throws -> [DisplayableSong]) {
        guard let controller else { return }
        let template = list(title, icon: "music.note")
        let controls = CarPlayPlaybackControls(template: template, container: container)
        playbackControls[ObjectIdentifier(template)] = controls
        controls.start()
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
                let items = Array(songItems(songs, container: container).prefix(CPListTemplate.maximumItemCount - 1))
                template.updateSections([CPListSection(items: [controls.row]), CPListSection(items: items)])

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
