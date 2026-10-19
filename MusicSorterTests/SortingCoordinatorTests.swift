//
//  SortingCoordinatorTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// The coordinator that starts every Sorting Run, from the foreground, background app
/// refresh or "Sort Now", driven through the fake library and an in-memory store.
@MainActor
struct SortingCoordinatorTests {
    let library = FakeMusicLibrary()
    let container: ModelContainer
    let coordinator: SortingCoordinator
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Schema(MusicSorterSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let now = now
        coordinator = SortingCoordinator(gateway: library, modelContext: container.mainContext, now: { now })
        container.mainContext.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: now))
        library.favorites = [LibrarySong(id: "A", title: "Song A", playCount: 12)]
    }

    @Test func runRequestedWhileOneIsInProgressWaitsForItInsteadOfStartingAnother() async throws {
        async let first = coordinator.sort()
        async let second = coordinator.sort()
        let summaries = try await [first, second]

        // A second run would have found nothing new to place.
        let expected = SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1, createdPlaylistCount: 1)
        #expect(summaries == [expected, expected])
        #expect(library.playlists.count == 1)
    }

    @Test func runRequestedAfterOneEndsStartsANewRun() async throws {
        try await coordinator.sort()
        library.favorites.append(LibrarySong(id: "B", title: "Song B", playCount: 30))

        let summary = try await coordinator.sort()

        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1, createdPlaylistCount: 0))
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
    }

    @Test func failedRunEndsSoTheNextRequestStartsAnew() async throws {
        try await coordinator.sort()
        library.favorites.append(LibrarySong(id: "B", title: "Song B", playCount: 30))
        library.appendsBeforeFailure = 0
        await #expect(throws: FakeMusicLibrary.FakeError.interrupted) {
            try await coordinator.sort()
        }
        #expect(!coordinator.isSorting)

        let summary = try await coordinator.sort()

        #expect(summary.placementCount == 1)
    }

    @Test func runRequestedWhileACancelledOneWindsDownStartsANewRun() async throws {
        try await coordinator.sort()
        library.favorites += [
            LibrarySong(id: "B", title: "Song B", playCount: 30),
            LibrarySong(id: "C", title: "Song C", playCount: 40),
        ]
        var laterRequest: Task<SortingRunSummary, any Error>?
        let cancelledRequest = Task { try await coordinator.sort() }
        library.onNextWrite = {
            cancelledRequest.cancel()
            laterRequest = Task { try await coordinator.sort() }
            // Lets the later request ask for a run while the cancelled one is still going.
            await Task.yield()
        }
        _ = try? await cancelledRequest.value

        let summary = try await #require(laterRequest).value

        // The cancelled run placed B before stopping; the new run places C.
        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1, createdPlaylistCount: 0))
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B", "C"])
        #expect(try AppState.current(in: container.mainContext).lastSortingRunAt == now)
    }

    @Test func cancellingTheRequestStopsTheRun() async throws {
        let request = Task { try await coordinator.sort() }
        request.cancel()

        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect(library.playlists.isEmpty)
        #expect(try AppState.current(in: container.mainContext).lastSortingRunAt == nil)
    }
}
