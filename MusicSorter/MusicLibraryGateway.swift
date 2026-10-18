//
//  MusicLibraryGateway.swift
//  MusicSorter
//

import Foundation

/// The Source Playlists the app reads from.
enum SourcePlaylist: String, Codable, CaseIterable {
    case favoriteSongs
}

/// A Song as read from a Source Playlist.
struct LibrarySong: Hashable, Sendable {
    /// The Apple Music catalog ID, which identifies the Song.
    var id: String
    var title: String
    /// `nil` when the Song isn't in the user's library.
    var playCount: Int?
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
