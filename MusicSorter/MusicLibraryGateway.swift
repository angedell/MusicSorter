//
//  MusicLibraryGateway.swift
//  MusicSorter
//

import Foundation

/// The Source Playlists the app reads from.
enum SourcePlaylist: String, Codable, CaseIterable {
    case favoriteSongs
    /// Kept up to date by the Shazam app when "Sync to Apple Music" is on (ADR 0002).
    case myShazamTracks

    /// How the Source Playlist reads in the UI. Kept apart from the name the gateway looks
    /// the playlist up by, which may differ by library language (#14).
    var displayName: String {
        switch self {
        case .favoriteSongs: "Favorite Songs"
        case .myShazamTracks: "My Shazam Tracks"
        }
    }
}

/// A Song as read from a Source Playlist.
struct LibrarySong: Hashable, Sendable {
    /// The Apple Music catalog ID, which identifies the Song.
    var id: String
    var title: String
    /// `nil` when the Song isn't in the user's library.
    var playCount: Int?
    /// Every genre listed for the Song, in order, possibly including the catch-all "Music".
    var genres: [String] = []
    /// The Song's credited artist, or `nil` if Apple Music doesn't give one.
    var artistName: String?
    /// The name of the first artist linked to the Song, e.g. "Daft Punk" for a Song
    /// credited to "Daft Punk & Pharrell Williams". `nil` when Apple Music links none.
    var firstArtistName: String?
    /// `nil` when Apple Music doesn't give a release date.
    var releaseDate: Date?
    /// The Source Playlists the Song was found in. Filled in by the Sorting Engine when it
    /// merges the Source Playlists; gateways leave it empty.
    var sources: Set<SourcePlaylist> = []
    /// When the app first found the Song in each Source Playlist it has ever been in,
    /// including ones it has since left. Filled in by the Sorting Engine; gateways leave
    /// it empty.
    var firstSeen: [SourcePlaylist: Date] = [:]
}

/// The app's only connection to the Apple Music library, and the only test seam.
protocol MusicLibraryGateway {
    /// The Songs of a Source Playlist, or `nil` if the playlist doesn't exist.
    func songs(in source: SourcePlaylist) async throws -> [LibrarySong]?

    /// Creates a playlist with the given name, holding the given Songs in order, and
    /// returns its ID. Either the playlist is created with all the Songs, or not at all.
    func createPlaylist(named name: String, songIDs: [String]) async throws -> String

    /// Appends a Song to the end of the playlist with the given ID. MusicKit adds one item
    /// at a time, so each append either fully succeeds or adds nothing.
    func append(songID: String, toPlaylistWithID playlistID: String) async throws
}
