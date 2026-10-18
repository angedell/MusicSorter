//
//  MusicSorterTests.swift
//  MusicSorterTests
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Drives whole Sorting Runs through the fake library and an in-memory store.
@MainActor
struct PlayCountRuleTests {
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

    @discardableResult
    private func addRule(_ name: String, playedAtLeast count: Int) -> Rule {
        let rule = Rule(name: name, conditions: [.playCountAtLeast(count)], createdAt: now)
        context.insert(rule)
        return rule
    }

    @discardableResult
    private func sort(at date: Date? = nil) async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: date ?? now)
    }

    private func song(_ id: String, plays: Int?) -> LibrarySong {
        LibrarySong(id: id, title: "Song \(id)", playCount: plays)
    }

    @Test func newRuleCreatesItsSortedPlaylistAndPlacesExistingMatchingSongs() async throws {
        library.favorites = [song("A", plays: 12), song("B", plays: 3), song("C", plays: 40)]
        addRule("Heavy Rotation", playedAtLeast: 10)

        let summary = try await sort()

        #expect(library.playlists.map(\.name) == ["Heavy Rotation · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "C"])
        #expect(summary == SortingRunSummary(placementCount: 2, createdPlaylistCount: 1))
    }

    @Test func ruleWithNoMatchingSongsStillCreatesItsSortedPlaylist() async throws {
        library.favorites = [song("A", plays: 1)]
        addRule("Heavy Rotation", playedAtLeast: 10)

        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == [])
        #expect(summary == SortingRunSummary(placementCount: 0, createdPlaylistCount: 1))
    }

    @Test func secondRunPlacesNothingNew() async throws {
        library.favorites = [song("A", plays: 12)]
        addRule("Heavy Rotation", playedAtLeast: 10)
        try await sort()

        let summary = try await sort()

        #expect(library.playlists.count == 1)
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A"])
        #expect(summary == SortingRunSummary(placementCount: 0, createdPlaylistCount: 0))
    }

    @Test func playCountBoundary() async throws {
        library.favorites = [song("Nine", plays: 9), song("Ten", plays: 10)]
        addRule("Ten Plus", playedAtLeast: 10)

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Ten Plus · Sorted") == ["Ten"])
    }

    @Test func songsNotInTheLibraryCountAsZeroPlays() async throws {
        library.favorites = [song("Catalog", plays: nil)]
        addRule("Any Plays", playedAtLeast: 0)
        addRule("Played Once", playedAtLeast: 1)

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Any Plays · Sorted") == ["Catalog"])
        #expect(library.songIDs(inPlaylistNamed: "Played Once · Sorted") == [])
    }

    @Test func songThatStartsMatchingLaterIsAppendedToTheEnd() async throws {
        library.favorites = [song("A", plays: 12), song("B", plays: 9)]
        addRule("Heavy Rotation", playedAtLeast: 10)
        try await sort()

        library.favorites = [song("A", plays: 13), song("B", plays: 10), song("C", plays: 50)]
        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B", "C"])
        #expect(summary == SortingRunSummary(placementCount: 2, createdPlaylistCount: 0))
    }

    @Test func songRemovedByHandIsNotReAdded() async throws {
        library.favorites = [song("A", plays: 12), song("B", plays: 20)]
        addRule("Heavy Rotation", playedAtLeast: 10)
        try await sort()

        library.removeByHand(songID: "A", fromPlaylistNamed: "Heavy Rotation · Sorted")
        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["B"])
        #expect(summary.placementCount == 0)
    }

    @Test func unfavoritedSongStaysPlacedAndIsNotReAddedWhenFavoritedAgain() async throws {
        library.favorites = [song("A", plays: 12)]
        addRule("Heavy Rotation", playedAtLeast: 10)
        try await sort()

        library.favorites = []
        try await sort()
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A"])

        library.favorites = [song("A", plays: 12)]
        let summary = try await sort()
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A"])
        #expect(summary.placementCount == 0)
    }

    @Test func renamedSortedPlaylistKeepsReceivingSongs() async throws {
        library.favorites = [song("A", plays: 12)]
        addRule("Heavy Rotation", playedAtLeast: 10)
        try await sort()

        library.rename(playlistNamed: "Heavy Rotation · Sorted", to: "My Bangers")
        library.favorites.append(song("B", plays: 30))
        let summary = try await sort()

        #expect(library.playlists.count == 1)
        #expect(library.songIDs(inPlaylistNamed: "My Bangers") == ["A", "B"])
        #expect(summary == SortingRunSummary(placementCount: 1, createdPlaylistCount: 0))
    }

    @Test func eachSortedPlaylistReportsItsSongCount() async throws {
        library.favorites = [song("A", plays: 12), song("B", plays: 30)]
        let rule = addRule("Heavy Rotation", playedAtLeast: 10)

        try await sort()

        #expect(rule.sortedPlaylists?.map(\.songCount) == [2])
    }

    @Test func runRecordsLastSortedTime() async throws {
        addRule("Heavy Rotation", playedAtLeast: 10)

        try await sort(at: now)

        #expect(try AppState.current(in: context).lastSortingRunAt == now)
    }
}
