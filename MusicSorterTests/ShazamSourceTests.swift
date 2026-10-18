//
//  ShazamSourceTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Sorting Runs over both Source Playlists, through the fake library and an in-memory store.
@MainActor
struct ShazamSourceTests {
    let library = FakeMusicLibrary()
    let container: ModelContainer
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Schema(MusicSorterSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var context: ModelContext { container.mainContext }

    private func addRule(_ name: String, conditions: [Condition]) {
        context.insert(Rule(name: name, conditions: conditions, createdAt: now))
    }

    @discardableResult
    private func sort() async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: now)
    }

    private func song(_ id: String, plays: Int? = 1) -> LibrarySong {
        LibrarySong(id: id, title: "Song \(id)", playCount: plays)
    }

    @Test func shazamedSongsAreSortedToo() async throws {
        library.favorites = [song("A")]
        library.shazamSongs = [song("S")]
        addRule("Everything", conditions: [.playCountAtLeast(0)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["A", "S"])
    }

    @Test func songInBothSourcesIsPlacedOnce() async throws {
        library.favorites = [song("A"), song("B")]
        library.shazamSongs = [song("B"), song("C")]
        addRule("Everything", conditions: [.playCountAtLeast(0)])
        try await sort()
        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["A", "B", "C"])

        library.favorites.append(song("D"))
        library.shazamSongs.append(song("D"))
        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["A", "B", "C", "D"])
        #expect(summary.placementCount == 1)
    }

    @Test func sourcePlaylistConditionMatchesOnlySongsFromThatSource() async throws {
        library.favorites = [song("Fav"), song("Both")]
        library.shazamSongs = [song("Both"), song("Shazam")]
        addRule("Favs", conditions: [.sourcePlaylistIs(.favoriteSongs)])
        addRule("Shazams", conditions: [.sourcePlaylistIs(.myShazamTracks)])

        try await sort()

        // A Song in both Source Playlists meets either Source Playlist Condition.
        #expect(library.songIDs(inPlaylistNamed: "Favs · Sorted") == ["Fav", "Both"])
        #expect(library.songIDs(inPlaylistNamed: "Shazams · Sorted") == ["Both", "Shazam"])
    }

    @Test func sourcePlaylistConditionCombinesWithOtherConditions() async throws {
        library.favorites = [song("FavHot", plays: 20)]
        library.shazamSongs = [song("ShazamHot", plays: 20), song("ShazamCold", plays: 2)]
        addRule("Hot Shazams", conditions: [.sourcePlaylistIs(.myShazamTracks), .playCountAtLeast(10)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Hot Shazams · Sorted") == ["ShazamHot"])
    }

    @Test func sourcePlaylistConditionRoundTripsThroughItsStoredEncoding() throws {
        let rule = Rule(name: "Shazams", conditions: [.sourcePlaylistIs(.myShazamTracks)], createdAt: now)

        #expect(rule.storedConditions == [.sourcePlaylistIs(.myShazamTracks)])
    }

    @Test func missingShazamPlaylistSortsFavoritesAndWarns() async throws {
        library.favorites = [song("A")]
        library.removeSourcePlaylist(.myShazamTracks)
        addRule("Everything", conditions: [.playCountAtLeast(0)])

        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["A"])
        #expect(summary.warnings == [.shazamPlaylistMissing])
        #expect(try AppState.current(in: context).isShazamPlaylistMissing)
    }

    @Test func presentShazamPlaylistGivesNoWarning() async throws {
        library.favorites = [song("A")]
        addRule("Everything", conditions: [.playCountAtLeast(0)])

        let summary = try await sort()

        #expect(summary.warnings.isEmpty)
        #expect(try !AppState.current(in: context).isShazamPlaylistMissing)
    }

    @Test func warningClearsOnTheFirstRunThatFindsTheShazamPlaylist() async throws {
        library.removeSourcePlaylist(.myShazamTracks)
        addRule("Everything", conditions: [.playCountAtLeast(0)])
        try await sort()
        #expect(try AppState.current(in: context).isShazamPlaylistMissing)

        library.shazamSongs = [song("S")]
        let summary = try await sort()

        #expect(summary.warnings.isEmpty)
        #expect(try !AppState.current(in: context).isShazamPlaylistMissing)
        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["S"])
    }

    @Test func sourcePlaylistsAreNeverModified() async throws {
        library.favorites = [song("A")]
        library.shazamSongs = [song("S")]
        addRule("Everything", conditions: [.playCountAtLeast(0)])
        try await sort()

        library.favorites.append(song("B"))
        try await sort()

        #expect(library.favorites.map(\.id) == ["A", "B"])
        #expect(library.shazamSongs.map(\.id) == ["S"])
        // Only the Sorted Playlist was ever created or appended to.
        #expect(library.playlists.map(\.name) == ["Everything · Sorted"])
    }
}
