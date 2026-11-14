import CarPlay
import Foundation
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

    @Test func nativeBrowsingTabsHaveLocalizedTitlesAndLoadingStates() throws {
        let root = CarPlaySceneDelegate().makeRootTemplate()
        let lists = root.templates.compactMap { $0 as? CPListTemplate }
        #expect(lists.count == 3)
        #expect(lists.map(\.title) == [String(localized: "Songs"), String(localized: "Albums"), String(localized: "Playlists")])
        #expect(lists.allSatisfy { $0.tabImage != nil && $0.emptyViewTitleVariants == [String(localized: "Loading…")] })
        #expect(lists.compactMap { $0.userInfo as? String } == ["songs", "albums", "playlists"])
    }
}
