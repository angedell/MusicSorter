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

    /// Creates a playlist with the given name and returns its ID.
    func createPlaylist(named name: String) async throws -> String

    /// Appends Songs, in order, to the end of the playlist with the given ID.
    func append(songIDs: [String], toPlaylistWithID playlistID: String) async throws
}
