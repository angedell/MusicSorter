//
//  MusicKitLibraryGateway.swift
//  MusicSorter
//

import Foundation
import MusicKit
import OSLog

/// The production Music Library Gateway, backed by MusicKit.
///
/// Built on the device findings recorded on #14:
/// - System playlists such as "Favorite Songs" have no distinguishing `kind` or curator,
///   so they're found by name.
/// - Songs read from a library playlist carry a library ID (`i.…`); their catalog ID is
///   only available inside the opaque `playParameters`.
/// - `playCount` is populated for library Songs.
final class MusicKitLibraryGateway: MusicLibraryGateway {
    /// Songs seen in the last read of a Source Playlist, keyed by catalog ID, so they can
    /// be added to a Sorted Playlist without another lookup.
    private var songsByCatalogID: [String: Song] = [:]

    /// Sorted Playlists already looked up or created this session, keyed by ID, so each
    /// append doesn't need another library request.
    private var playlistsByID: [String: Playlist] = [:]

    /// Each Song's first linked artist (`nil` when it has none), keyed by catalog ID.
    /// Linked artists come only from the catalog, so they're looked up once per session.
    private var firstArtistNamesByCatalogID: [String: String?] = [:]

    func songs(in source: SourcePlaylist) async throws -> [LibrarySong]? {
        let start = ContinuousClock.now
        defer { Self.logger.info("Read \(source.rawValue) in \(ContinuousClock.now - start)") }
        guard let playlist = try await libraryPlaylist(named: source.libraryName) else {
            return nil
        }
        guard let firstEntries = try await playlist.with([.entries]).entries else {
            return []
        }

        var songs: [LibrarySong] = []
        for entry in try await Self.allItems(startingWith: firstEntries) {
            guard case .song(let song) = entry.item else { continue }
            // A Song is identified by its catalog ID. One without a catalog ID can't be
            // identified reliably, so it's left out rather than given a library ID.
            guard let catalogID = Self.catalogID(of: song) else {
                Self.logger.info("Skipped \(song.id.rawValue): no catalog ID")
                continue
            }
            songsByCatalogID[catalogID] = song
            songs.append(LibrarySong(
                id: catalogID,
                title: song.title,
                playCount: song.playCount,
                genres: song.genreNames,
                artistName: song.artistName.isEmpty ? nil : song.artistName,
                releaseDate: song.releaseDate
            ))
        }
        await loadFirstArtistNames(ofCatalogIDs: songs.map(\.id))
        for index in songs.indices {
            songs[index].firstArtistName = firstArtistNamesByCatalogID[songs[index].id] ?? nil
        }
        return songs
    }

    func createPlaylist(named name: String, songIDs: [String]) async throws -> String {
        let start = ContinuousClock.now
        var songs: [Song] = []
        for songID in songIDs {
            songs.append(try await song(withCatalogID: songID))
        }
        let playlist = try await MusicLibrary.shared.createPlaylist(name: name, items: songs)
        playlistsByID[playlist.id.rawValue] = playlist
        Self.logger.info("Created playlist \(playlist.id.rawValue) with \(songs.count) songs in \(ContinuousClock.now - start)")
        return playlist.id.rawValue
    }

    func append(songID: String, toPlaylistWithID playlistID: String) async throws {
        let start = ContinuousClock.now
        let playlist = try await playlist(withID: playlistID)
        let song = try await song(withCatalogID: songID)
        playlistsByID[playlistID] = try await MusicLibrary.shared.add(song, to: playlist)
        Self.logger.debug("Appended \(songID) to \(playlistID) in \(ContinuousClock.now - start)")
    }

    // MARK: Helpers

    private static let logger = Logger(subsystem: "it.angedell.MusicSorter", category: "MusicKitLibraryGateway")

    private func playlist(withID playlistID: String) async throws -> Playlist {
        if let playlist = playlistsByID[playlistID] {
            return playlist
        }
        let start = ContinuousClock.now
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlistID))
        guard let playlist = try await request.response().items.first else {
            throw GatewayError.playlistNotFound(playlistID)
        }
        Self.logger.info("Looked up playlist \(playlistID) in \(ContinuousClock.now - start)")
        playlistsByID[playlistID] = playlist
        return playlist
    }

    /// Looks up the linked artists of the Songs not looked up yet, many Songs per catalog
    /// request.
    private func loadFirstArtistNames(ofCatalogIDs catalogIDs: [String]) async {
        let missing = Array(Set(catalogIDs).subtracting(firstArtistNamesByCatalogID.keys))
        guard !missing.isEmpty else { return }
        let start = ContinuousClock.now
        for batchStart in stride(from: 0, to: missing.count, by: Self.catalogBatchSize) {
            let batch = missing[batchStart..<min(batchStart + Self.catalogBatchSize, missing.count)]
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: batch.map { MusicItemID($0) })
            request.properties = [.artists]
            // Without linked artists only grouping by artist is affected, so a failed lookup
            // leaves those Songs out of artist Groups until a later run rather than failing
            // the whole run. Nothing is cached, so the lookup is retried next time.
            let catalogSongs: MusicItemCollection<Song>
            do {
                catalogSongs = try await request.response().items
            } catch {
                Self.logger.error("Couldn't look up linked artists: \(error)")
                continue
            }
            for song in catalogSongs {
                firstArtistNamesByCatalogID[song.id.rawValue] = .some(song.artists?.first?.name)
            }
            // Songs the catalog doesn't return have no linked artist to group by.
            for catalogID in batch where firstArtistNamesByCatalogID[catalogID] == nil {
                firstArtistNamesByCatalogID[catalogID] = .some(nil)
            }
        }
        Self.logger.info("Looked up linked artists of \(missing.count) songs in \(ContinuousClock.now - start)")
    }

    /// How many Songs one catalog request looks up.
    private static let catalogBatchSize = 100

    private func libraryPlaylist(named name: String) async throws -> Playlist? {
        let firstPlaylists = try await MusicLibraryRequest<Playlist>().response().items
        let candidates = try await Self.allItems(startingWith: firstPlaylists)
            .filter { $0.name == name }
        // System playlists have no kind or curator; prefer them over a user's look-alike.
        return candidates.first { $0.kind == nil && $0.curatorName == nil } ?? candidates.first
    }

    /// Every item of a collection, fetching any further batches MusicKit hasn't loaded yet.
    private static func allItems<Item: MusicItem>(
        startingWith firstBatch: MusicItemCollection<Item>
    ) async throws -> [Item] {
        var items = Array(firstBatch)
        var batch = firstBatch
        while batch.hasNextBatch, let next = try await batch.nextBatch() {
            items.append(contentsOf: next)
            batch = next
        }
        return items
    }

    private func song(withCatalogID catalogID: String) async throws -> Song {
        if let song = songsByCatalogID[catalogID] {
            return song
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(catalogID))
        guard let song = try await request.response().items.first else {
            throw GatewayError.songNotFound(catalogID)
        }
        return song
    }

    /// Reads the catalog ID out of a Song's opaque play parameters. MusicKit doesn't expose
    /// it directly on library Songs.
    private static func catalogID(of song: Song) -> String? {
        struct Parameters: Decodable {
            var catalogId: String?
        }
        guard let playParameters = song.playParameters,
              let data = try? JSONEncoder().encode(playParameters) else { return nil }
        return (try? JSONDecoder().decode(Parameters.self, from: data))?.catalogId
    }

    enum GatewayError: LocalizedError {
        case playlistNotFound(String)
        case songNotFound(String)

        var errorDescription: String? {
            switch self {
            case .playlistNotFound(let id): "Couldn't find the Sorted Playlist \(id) in Apple Music."
            case .songNotFound(let id): "Couldn't find the song \(id) in Apple Music."
            }
        }
    }
}

private extension SourcePlaylist {
    /// The playlist's name in the user's library. Confirmed on an English-named library;
    /// see #14 for the open question about other languages.
    var libraryName: String {
        switch self {
        case .favoriteSongs: "Favorite Songs"
        case .myShazamTracks: "My Shazam Tracks"
        }
    }
}
