//
//  SetupTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// First-run setup and the blocked Sorting Runs behind the blocking screens, driven through
/// the fake library and an in-memory store.
@MainActor
struct SetupTests {
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
    private func sort(at date: Date? = nil) async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: date ?? now)
    }

    private func rules() throws -> [Rule] {
        try context.fetch(FetchDescriptor<Rule>())
    }

    // MARK: Blocked Sorting Runs

    @Test(arguments: [SortingBlocker.noMusicAccess, .noSubscription])
    func blockedRunReturnsABlockedSummaryAndChangesNothing(blocker: SortingBlocker) async throws {
        library.favorites = [LibrarySong(id: "A", title: "Song A", playCount: 12)]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: now))
        library.blocker = blocker

        let summary = try await sort()

        #expect(summary == SortingRunSummary(blocker: blocker))
        #expect(library.playlists.isEmpty)
        #expect(try AppState.current(in: context).lastSortingRunAt == nil)
    }

    @Test(arguments: [SortingBlocker.noMusicAccess, .noSubscription])
    func blockedRunAddsNothingToExistingSortedPlaylists(blocker: SortingBlocker) async throws {
        library.favorites = [LibrarySong(id: "A", title: "Song A", playCount: 12)]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: now))
        try await sort()
        library.favorites.append(LibrarySong(id: "B", title: "Song B", playCount: 30))
        library.blocker = blocker

        let summary = try await sort(at: now.addingTimeInterval(60))

        #expect(summary == SortingRunSummary(blocker: blocker))
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A"])
        #expect(library.appendCount == 0)
        #expect(try AppState.current(in: context).lastSortingRunAt == now)
    }

    @Test func runOnceUnblockedSortsAsUsual() async throws {
        library.favorites = [LibrarySong(id: "A", title: "Song A", playCount: 12)]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: now))
        library.blocker = .noSubscription
        try await sort()
        library.blocker = nil

        let summary = try await sort()

        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1, createdPlaylistCount: 1))
    }

    // MARK: Setup's Shazam check

    @Test func shazamCheckFindsTheMissingPlaylistAndChangesNothing() async throws {
        library.favorites = [LibrarySong(id: "A", title: "Song A", playCount: 12)]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: now))
        let coordinator = SortingCoordinator(gateway: library, modelContext: context)
        #expect(try await coordinator.sourcePlaylistExists(.myShazamTracks))

        library.removeSourcePlaylist(.myShazamTracks)

        #expect(try await coordinator.sourcePlaylistExists(.myShazamTracks) == false)
        #expect(library.playlists.isEmpty)
        #expect(try AppState.current(in: context).lastSortingRunAt == nil)
    }

    // MARK: Starter Rules

    @Test func acceptingPlayedTwentyTimesCreatesExactlyThatRule() async throws {
        StarterRule.playedTwentyTimes.add(to: context, now: now)

        let rules = try rules()
        #expect(rules.count == 1)
        #expect(rules.first?.name == "Played 20+ Times")
        #expect(rules.first?.conditions == [.playCountAtLeast(20)])
        #expect(rules.first?.isGrouped == false)

        library.favorites = [
            LibrarySong(id: "A", title: "Song A", playCount: 20),
            LibrarySong(id: "B", title: "Song B", playCount: 19),
        ]
        try await sort()
        #expect(library.playlists.map(\.name) == ["Played 20+ Times · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Played 20+ Times · Sorted") == ["A"])
    }

    @Test func acceptingGroupByPrimaryGenreCreatesExactlyThatRule() async throws {
        StarterRule.groupByPrimaryGenre.add(to: context, now: now)

        let rules = try rules()
        #expect(rules.count == 1)
        #expect(rules.first?.name == "By Genre")
        #expect(rules.first?.conditions == [])
        #expect(rules.first?.grouping == .primaryGenre)
        #expect(rules.first?.groupThreshold == 5)

        library.favorites = (1...5).map { LibrarySong(id: "J\($0)", title: "Jazz \($0)", genres: ["Jazz", "Music"]) }
            + [LibrarySong(id: "R", title: "Rock", genres: ["Rock"])]
        try await sort()
        #expect(library.playlists.map(\.name) == ["Jazz · Sorted"])
    }

    @Test func acceptingOneSuggestionLeavesTheOtherUncreated() async throws {
        StarterRule.groupByPrimaryGenre.add(to: context, now: now)

        #expect(try rules().map(\.name) == ["By Genre"])
        #expect(StarterRule.playedTwentyTimes.isAdded(among: try rules()) == false)
        #expect(StarterRule.groupByPrimaryGenre.isAdded(among: try rules()))
    }
}
