//
//  InterruptedRunTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Sorting Runs that stop part-way, because an add failed or background time expired,
/// driven through the fake library and an in-memory store.
@MainActor
struct InterruptedRunTests {
    let library = FakeMusicLibrary()
    let container: ModelContainer
    let firstRun = Date(timeIntervalSince1970: 1_800_000_000)
    let interruptedRun = Date(timeIntervalSince1970: 1_800_003_600)
    let nextRun = Date(timeIntervalSince1970: 1_800_007_200)

    init() throws {
        container = try ModelContainer(
            for: Schema(MusicSorterSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func sort(at date: Date) async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: date)
    }

    private func song(_ id: String, plays: Int = 20, genre: String = "Jazz") -> LibrarySong {
        LibrarySong(id: id, title: "Song \(id)", playCount: plays, genres: [genre])
    }

    private var lastSortedAt: Date? {
        get throws { try AppState.current(in: context).lastSortingRunAt }
    }

    /// The Song IDs recorded as placed in the playlist with this name.
    private func placedSongIDs(inPlaylistNamed name: String) throws -> [String] {
        let records = try context.fetch(FetchDescriptor<SortedPlaylistRecord>())
        let record = try #require(records.first { $0.name == name })
        return (record.placements ?? []).map(\.songID).sorted()
    }

    @Test func failedAddLeavesLastSortedAtThePreviousRun() async throws {
        library.favorites = [song("A")]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: firstRun))
        try await sort(at: firstRun)

        library.favorites += [song("B")]
        library.appendsBeforeFailure = 0
        await #expect(throws: FakeMusicLibrary.FakeError.interrupted) {
            try await sort(at: interruptedRun)
        }

        #expect(try lastSortedAt == firstRun)
    }

    @Test func failedAddsAcrossGroupsAreCompletedByTheNextRunWithoutDuplicates() async throws {
        library.favorites = [song("J1", genre: "Jazz"), song("R1", genre: "Rock")]
        context.insert(Rule(name: "By Genre", conditions: [], grouping: .primaryGenre, groupThreshold: 1, createdAt: firstRun))
        try await sort(at: firstRun)

        library.favorites += [
            song("J2", genre: "Jazz"), song("R2", genre: "Rock"),
            song("J3", genre: "Jazz"), song("R3", genre: "Rock"),
        ]
        library.appendsBeforeFailure = 3
        await #expect(throws: FakeMusicLibrary.FakeError.interrupted) {
            try await sort(at: interruptedRun)
        }
        try await sort(at: nextRun)

        for (name, songs) in [("Jazz · Sorted", ["J1", "J2", "J3"]), ("Rock · Sorted", ["R1", "R2", "R3"])] {
            #expect(library.songIDs(inPlaylistNamed: name)?.sorted() == songs)
            #expect(try placedSongIDs(inPlaylistNamed: name) == songs)
        }
        #expect(library.playlists.count == 2)
        #expect(try lastSortedAt == nextRun)
    }

    @Test func cancelledRunStopsBetweenAddsAndLeavesLastSortedAlone() async throws {
        library.favorites = [song("A")]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: firstRun))
        try await sort(at: firstRun)

        library.favorites += [song("B"), song("C"), song("D")]
        let run = Task { try await sort(at: interruptedRun) }
        library.onNextWrite = { run.cancel() }
        await #expect(throws: CancellationError.self) {
            try await run.value
        }

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
        #expect(try placedSongIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
        #expect(try lastSortedAt == firstRun)
    }

    @Test func runAfterACancelledRunCompletesTheRemainingPlacements() async throws {
        library.favorites = [song("A")]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: firstRun))
        try await sort(at: firstRun)
        library.favorites += [song("B"), song("C"), song("D")]
        let run = Task { try await sort(at: interruptedRun) }
        library.onNextWrite = { run.cancel() }
        _ = try? await run.value

        let summary = try await sort(at: nextRun)

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B", "C", "D"])
        #expect(try placedSongIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B", "C", "D"])
        #expect(summary == SortingRunSummary(placementCount: 2, createdPlaylistCount: 0))
        #expect(try lastSortedAt == nextRun)
    }

    @Test func playlistCreatedAsTheRunIsCancelledIsRecordedAndNotCreatedAgain() async throws {
        library.favorites = [song("A")]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: firstRun))
        let run = Task { try await sort(at: interruptedRun) }
        library.onNextWrite = { run.cancel() }
        _ = try? await run.value

        try await sort(at: nextRun)

        #expect(library.playlists.map(\.name) == ["Heavy Rotation · Sorted"])
        #expect(try placedSongIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A"])
    }

    @Test func runCancelledBeforeItStartsPlacesNothing() async throws {
        library.favorites = [song("A")]
        context.insert(Rule(name: "Heavy Rotation", conditions: [.playCountAtLeast(10)], createdAt: firstRun))

        let run = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await sort(at: firstRun)
        }
        await #expect(throws: CancellationError.self) {
            try await run.value
        }

        #expect(library.playlists.isEmpty)
        #expect(try lastSortedAt == nil)
    }
}
