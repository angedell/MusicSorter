//
//  PausedRuleTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Pausing a Rule whose Sorted Playlist was deleted in the Music app, and resuming it,
/// driven through whole Sorting Runs over the fake library and an in-memory store.
@MainActor
struct PausedRuleTests {
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
    private func addRule(_ name: String, conditions: [Condition], grouping: Grouping? = nil, threshold: Int = 1) -> Rule {
        let rule = Rule(name: name, conditions: conditions, grouping: grouping, groupThreshold: threshold, createdAt: now)
        context.insert(rule)
        return rule
    }

    @discardableResult
    private func sort() async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: now)
    }

    private func song(_ id: String, plays: Int, genres: [String] = []) -> LibrarySong {
        LibrarySong(id: id, title: "Song \(id)", playCount: plays, genres: genres)
    }

    // MARK: Detecting

    @Test func deletingASortedPlaylistPausesItsRule() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()

        library.delete(playlistNamed: "Heavy Rotation · Sorted")
        let summary = try await sort()

        #expect(rule.status == .paused)
        #expect(rule.deletedSortedPlaylists.map(\.name) == ["Heavy Rotation · Sorted"])
        #expect(summary == SortingRunSummary(warnings: [.rulePaused("Heavy Rotation")]))
    }

    @Test func pausedRuleIsNotAppliedAndItsPlaylistIsNotRecreated() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()
        library.delete(playlistNamed: "Heavy Rotation · Sorted")
        try await sort()

        library.favorites.append(song("B", plays: 30))
        let summary = try await sort()

        #expect(library.playlists.isEmpty)
        #expect(rule.status == .paused)
        #expect(summary == SortingRunSummary())
    }

    @Test func otherRulesKeepSortingWhileOneIsPaused() async throws {
        library.favorites = [song("A", plays: 20)]
        addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        let other = addRule("Everything", conditions: [])
        try await sort()

        library.delete(playlistNamed: "Heavy Rotation · Sorted")
        library.favorites.append(song("B", plays: 30))
        try await sort()

        #expect(other.status == .active)
        #expect(library.songIDs(inPlaylistNamed: "Everything · Sorted") == ["A", "B"])
    }

    @Test func aDetachedPlaylistBeingDeletedDoesNotPauseTheRule() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()
        rule.startOver()
        try await sort()

        library.delete(playlistNamed: "Heavy Rotation · Sorted")
        library.favorites.append(song("B", plays: 30))
        try await sort()

        #expect(rule.status == .active)
        #expect(library.playlists.map(\.songIDs) == [["A", "B"]])
    }

    @Test func deletingAnyGroupPlaylistPausesTheWholeGroupedRule() async throws {
        library.favorites = [song("A", plays: 1, genres: ["Jazz"]), song("B", plays: 1, genres: ["Rock"])]
        let rule = addRule("By Genre", conditions: [], grouping: .primaryGenre)
        try await sort()

        library.delete(playlistNamed: "Jazz · Sorted")
        library.favorites.append(song("C", plays: 1, genres: ["Rock"]))
        let summary = try await sort()

        #expect(rule.status == .paused)
        #expect(library.songIDs(inPlaylistNamed: "Rock · Sorted") == ["B"])
        #expect(summary == SortingRunSummary(warnings: [.rulePaused("By Genre")]))
    }

    // MARK: Resuming

    @Test func resumingCreatesANewSortedPlaylistWithAllMatchingSongs() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()
        library.delete(playlistNamed: "Heavy Rotation · Sorted")
        try await sort()
        library.favorites.append(song("B", plays: 30))

        rule.resume()
        let summary = try await sort()

        #expect(rule.status == .active)
        #expect(rule.deletedSortedPlaylists.isEmpty)
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
        #expect(rule.currentSortedPlaylist?.playlistID == library.playlists.last?.id)
        #expect(summary == SortingRunSummary(placementCount: 2, createdPlaylistCount: 1))
    }

    @Test func resumingAGroupedRuleRecreatesOnlyTheDeletedGroupPlaylist() async throws {
        library.favorites = [song("A", plays: 1, genres: ["Jazz"]), song("B", plays: 1, genres: ["Rock"])]
        let rule = addRule("By Genre", conditions: [], grouping: .primaryGenre)
        try await sort()
        library.delete(playlistNamed: "Jazz · Sorted")
        try await sort()
        library.favorites.append(song("C", plays: 1, genres: ["Rock"]))

        rule.resume()
        let summary = try await sort()

        #expect(library.playlists.map(\.name) == ["Rock · Sorted", "Jazz · Sorted"])
        #expect(library.playlists.map(\.songIDs) == [["B", "C"], ["A"]])
        #expect(summary == SortingRunSummary(placementCount: 2, createdPlaylistCount: 1))
        #expect(rule.groupPlaylists.map(\.name) == ["Jazz · Sorted", "Rock · Sorted"])
    }
}
