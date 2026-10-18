//
//  FakeMusicLibrary.swift
//  MusicSorterTests
//

import Foundation
@testable import MusicSorter

/// An in-memory Apple Music library that records the playlists created and the Songs
/// appended to them.
final class FakeMusicLibrary: MusicLibraryGateway {
    struct FakePlaylist {
        var id: String
        var name: String
        var songIDs: [String]
    }

    var sourcePlaylists: [SourcePlaylist: [LibrarySong]] = [:]
    private(set) var playlists: [FakePlaylist] = []

    var favorites: [LibrarySong] {
        get { sourcePlaylists[.favoriteSongs] ?? [] }
        set { sourcePlaylists[.favoriteSongs] = newValue }
    }

    /// The Song IDs in the playlist currently carrying `name`, or `nil` if there is none.
    func songIDs(inPlaylistNamed name: String) -> [String]? {
        playlists.first { $0.name == name }?.songIDs
    }

    /// Simulates the user renaming a playlist in the Music app.
    func rename(playlistNamed name: String, to newName: String) {
        guard let index = playlists.firstIndex(where: { $0.name == name }) else { return }
        playlists[index].name = newName
    }

    /// Simulates the user removing a Song from a playlist by hand in the Music app.
    func removeByHand(songID: String, fromPlaylistNamed name: String) {
        guard let index = playlists.firstIndex(where: { $0.name == name }) else { return }
        playlists[index].songIDs.removeAll { $0 == songID }
    }

    // MARK: MusicLibraryGateway

    func songs(in source: SourcePlaylist) async throws -> [LibrarySong]? {
        sourcePlaylists[source]
    }

    func createPlaylist(named name: String) async throws -> String {
        let id = "p.\(playlists.count + 1)"
        playlists.append(FakePlaylist(id: id, name: name, songIDs: []))
        return id
    }

    func append(songIDs: [String], toPlaylistWithID playlistID: String) async throws {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            throw FakeError.noSuchPlaylist
        }
        playlists[index].songIDs.append(contentsOf: songIDs)
    }

    enum FakeError: Error {
        case noSuchPlaylist
    }
}
