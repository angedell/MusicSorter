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

    /// Every Source Playlist exists, empty, until a test fills or removes it.
    private var sourcePlaylists: [SourcePlaylist: [LibrarySong]] = [
        .favoriteSongs: [],
        .myShazamTracks: [],
    ]
    private(set) var playlists: [FakePlaylist] = []

    var favorites: [LibrarySong] {
        get { sourcePlaylists[.favoriteSongs] ?? [] }
        set { sourcePlaylists[.favoriteSongs] = newValue }
    }

    var shazamSongs: [LibrarySong] {
        get { sourcePlaylists[.myShazamTracks] ?? [] }
        set { sourcePlaylists[.myShazamTracks] = newValue }
    }

    /// Simulates a Source Playlist that doesn't exist, e.g. "My Shazam Tracks" when
    /// "Sync to Apple Music" is off in Shazam.
    func removeSourcePlaylist(_ source: SourcePlaylist) {
        sourcePlaylists[source] = nil
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

    /// Simulates the user deleting a playlist in the Music app.
    func delete(playlistNamed name: String) {
        guard let index = playlists.firstIndex(where: { $0.name == name }) else { return }
        playlists.remove(at: index)
    }

    /// Simulates the user removing a Song from a playlist by hand in the Music app.
    func removeByHand(songID: String, fromPlaylistNamed name: String) {
        guard let index = playlists.firstIndex(where: { $0.name == name }) else { return }
        playlists[index].songIDs.removeAll { $0 == songID }
    }

    /// Simulates denied Music access or no Apple Music subscription; `nil` lets runs sort.
    var blocker: SortingBlocker?

    // MARK: MusicLibraryGateway

    func sortingBlocker() async -> SortingBlocker? {
        blocker
    }

    func songs(in source: SourcePlaylist) async throws -> [LibrarySong]? {
        sourcePlaylists[source]
    }

    func sourcePlaylistExists(_ source: SourcePlaylist) async throws -> Bool {
        sourcePlaylists[source] != nil
    }

    /// How many playlists have been created, so IDs stay unique after a deletion.
    private var createdPlaylistCount = 0

    func createPlaylist(named name: String, songIDs: [String]) async throws -> String {
        createdPlaylistCount += 1
        let id = "p.\(createdPlaylistCount)"
        playlists.append(FakePlaylist(id: id, name: name, songIDs: songIDs))
        try await didWrite()
        return id
    }

    func existingPlaylistIDs(among playlistIDs: Set<String>) async throws -> Set<String> {
        playlistIDs.intersection(playlists.map(\.id))
    }

    /// How many times `append` succeeded.
    private(set) var appendCount = 0

    func append(songID: String, toPlaylistWithID playlistID: String) async throws {
        if let remaining = appendsBeforeFailure {
            guard remaining > 0 else {
                appendsBeforeFailure = nil
                throw FakeError.interrupted
            }
            appendsBeforeFailure = remaining - 1
        }
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            throw FakeError.noSuchPlaylist
        }
        playlists[index].songIDs.append(songID)
        appendCount += 1
        try await didWrite()
    }

    /// When set, this many appends succeed and the next one fails, simulating a run that
    /// is interrupted part-way (e.g. an add failing).
    var appendsBeforeFailure: Int?

    /// Called once, right after the next playlist is created or Song appended, e.g. to
    /// cancel the Sorting Run mid-write as when background time expires.
    var onNextWrite: (() async -> Void)?

    /// Like MusicKit, a write whose task was cancelled while it ran reports the
    /// cancellation even though the change already reached the library.
    private func didWrite() async throws {
        let onWrite = onNextWrite
        onNextWrite = nil
        await onWrite?()
        try Task.checkCancellation()
    }

    enum FakeError: Error {
        case noSuchPlaylist
        case interrupted
    }
}
