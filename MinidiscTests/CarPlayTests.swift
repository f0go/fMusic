import CarPlay
import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("CarPlay integration")
@MainActor
struct CarPlayTests {
    @Test func builtAppRegistersCarPlayScene() throws {
        // Xcode's generated scene manifest must not discard the custom CarPlay role.
        let manifest = try #require(Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any])
        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let scenes = try #require(configurations["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]])
        #expect(scenes.first?["UISceneClassName"] as? String == "CPTemplateApplicationScene")
        #expect(scenes.first?["UISceneDelegateClassName"] as? String == "Minidisc.CarPlaySceneDelegate")
    }

    @Test func homeIsTheRootWithLibraryAndDirectSiri() {
        let root = CarPlaySceneDelegate().makeRootTemplate()
        #expect(root.title == String(localized: "Home"))
        #expect(root.userInfo as? String == "home")
        #expect(root.leadingNavigationBarButtons.first?.title == String(localized: "Library"))
        #expect(root.trailingNavigationBarButtons.isEmpty)
        #expect(root.emptyViewTitleVariants == [String(localized: "Loading…")])
    }

    @Test func homeUsesNativeSiriMediaRequests() {
        let home = CarPlaySceneDelegate().makeRootTemplate()
        #expect(home.assistantCellConfiguration?.assistantAction == .playMedia)
        #expect(home.assistantCellConfiguration?.visibility == .always)
        #expect(home.assistantCellConfiguration?.position == .top)
    }

    @Test func favoritePreviewRanksByPlayCountAndKeepsTheFullList() {
        let songs = (0..<8).map { (index: Int) -> Song in
            Song(id: String(index), title: "Song \(index)", playCount: index)
        }
        let ranked = CarPlayHomeSection.rankedFavorites(songs)
        #expect(ranked.prefix(5).map(\.id) == ["7", "6", "5", "4", "3"])
        #expect(ranked.count == 8)
        #expect(Set(ranked.map(\.id)) == Set(songs.map(\.id)))
    }

    @Test func missingAndEqualPlayCountsKeepStableOrder() {
        let songs = [Song(id: "a", title: "A", playCount: 2),
                     Song(id: "b", title: "B", playCount: 2),
                     Song(id: "c", title: "C"), Song(id: "d", title: "D", playCount: 0)]
        #expect(CarPlayHomeSection.rankedFavorites(songs).map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func trackListControlsUseSharedPlayerModesAndMutualExclusion() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CarPlayControls.\(UUID())"))
        let container = try AppContainer(inMemory: true, userDefaults: defaults)
        let template = CPListTemplate(title: "Fixture", sections: [])
        let controls = CarPlayPlaybackControls(template: template, container: container)
        controls.start()
        defer { controls.stop() }
        #expect(controls.row.elements.count == 4)
        await controls.perform(.shuffle)
        #expect(container.playerState.isShuffled)
        await controls.perform(.repeatMode)
        #expect(container.playerState.repeatMode == .all)
        await controls.perform(.repeatMode)
        #expect(container.playerState.repeatMode == .one)
        await controls.perform(.endless)
        #expect(container.playerState.isAutoExtendEnabled)
        #expect(!container.playerState.isShuffled)
        #expect(container.playerState.repeatMode == .off)
        await controls.perform(.musicalMix)
        #expect(container.crossfadeSettings.musicalMixEnabled)
        #expect(defaults.bool(forKey: "minidisc.musicalMix.enabled"))
        controls.stop()
        await controls.perform(.musicalMix)
        #expect(container.crossfadeSettings.musicalMixEnabled)
    }

    @Test func trackListControlsObservePhoneChangesAndDisableEndlessForLocalFiles() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CarPlayControls.\(UUID())"))
        let container = try AppContainer(inMemory: true, userDefaults: defaults)
        let template = CPListTemplate(title: "Fixture", sections: [])
        let controls = CarPlayPlaybackControls(template: template, container: container)
        controls.start()
        defer { controls.stop() }
        container.playerState.currentTrack = LocalMusicStore.placeholder(
            LocalFileReference(folderID: UUID(), relativePath: "Local.wav")).song
        container.playerState.repeatMode = .one
        container.crossfadeSettings.musicalMixEnabled = true
        for _ in 0..<20 {
            if controls.snapshot?.localTrack == true && controls.snapshot?.musicalMix == true { break }
            await Task.yield()
        }
        #expect(controls.snapshot?.repeatMode == .one)
        #expect(controls.snapshot?.musicalMix == true)
        #expect(controls.row.elements[2].isEnabled == false)
        await controls.perform(.endless)
        #expect(!container.playerState.isAutoExtendEnabled)
    }

}
