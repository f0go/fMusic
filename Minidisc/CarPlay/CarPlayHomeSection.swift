import Foundation
import SwiftSonic

/// The phone's Home sources and ordering, rendered with native CarPlay sections.
@MainActor
struct CarPlayHomeSection {
    enum Content {
        case songs([DisplayableSong])
        case albums([AlbumID3])
        case playlists([Playlist])
        case artists([ArtistID3])
    }
    let title: String
    let content: Content

    static func content(feed: HomeFeedViewModel?, container: AppContainer) -> [Self] {
        let local = container.localMusic.catalog
        guard container.serverState.activeServer != nil, let feed else {
            return localSections(local)
        }
        let online = container.serverState.isOnline
        let favorites = online ? feed.favorites : container.offlineLibrary.snapshot.favorites
        var sections: [Self] = []
        func albums(_ title: LocalizedStringResource, _ albums: [AlbumID3]) {
            let visible = container.visibleAlbums(albums)
            if !visible.isEmpty { sections.append(.init(title: String(localized: title), content: .albums(visible))) }
        }
        let playlists = container.visiblePlaylists(feed.topPicks)
        if !playlists.isEmpty {
            sections.append(.init(title: String(localized: "Your Playlists"), content: .playlists(playlists)))
        }
        let songs = favorites.songs.map { DisplayableSong(from: $0) }
        if !songs.isEmpty {
            sections.append(.init(title: String(localized: "Your Favorite Songs"), content: .songs(songs)))
        }
        albums("Your Favorite Albums", favorites.albums)
        albums("Recently Played", feed.recentlyPlayed)
        albums("In Heavy Rotation", feed.heavyRotation)
        albums("Rediscover", feed.rediscovery)
        albums("Recently Added from Your Artists", feed.relevantAdditions)
        albums("Recently Added", AlbumSort.recentlyAdded.sorted(container.visibleAlbums(feed.otherAdditions) + local.albums))
        for genre in feed.genreShelves {
            let visible = container.visibleAlbums(genre.albums)
            if !visible.isEmpty { sections.append(.init(title: genre.name, content: .albums(visible))) }
        }
        if !online, sections.isEmpty { albums("Albums", container.offlineLibrary.snapshot.albums + local.albums) }
        return sections
    }

    /// Counts are supplied by the music server (including plays from other clients).
    /// Keep the source order for ties and for servers that omit play counts.
    static func rankedFavorites(_ songs: [Song]) -> [Song] {
        songs.enumerated().sorted {
            let left = $0.element.playCount ?? 0
            let right = $1.element.playCount ?? 0
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    static func localSections(_ local: LocalMusicCatalog) -> [Self] {
        var sections: [Self] = []
        if !local.albums.isEmpty {
            sections.append(.init(title: String(localized: "Recently Added"), content: .albums(AlbumSort.recentlyAdded.sorted(local.albums))))
        }
        if !local.artists.isEmpty {
            sections.append(.init(title: String(localized: "Artists"), content: .artists(local.artists)))
        }
        return sections
    }
}
