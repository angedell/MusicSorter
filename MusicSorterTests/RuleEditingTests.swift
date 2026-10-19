//
//  RuleEditingTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Editing, starting over and deleting Rules, driven through whole Sorting Runs over the
/// fake library and an in-memory store.
@MainActor
struct RuleEditingTests {
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

    // MARK: Editing

    @Test func looseningARulePlacesAdditionalSongsOnTheNextRun() async throws {
        library.favorites = [song("A", plays: 20), song("B", plays: 6), song("C", plays: 1)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()

        rule.conditions = [.playCountAtLeast(5)]
        let summary = try await sort()

        #expect(library.playlists.map(\.name) == ["Heavy Rotation · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1))
    }

    @Test func tighteningARuleKeepsSongsAlreadyPlaced() async throws {
        library.favorites = [song("A", plays: 20), song("B", plays: 6)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(5)])
        try await sort()

        rule.conditions = [.playCountAtLeast(10)]
        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
    }

    @Test func renamingARuleKeepsItsSortedPlaylistAndItsName() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()

        rule.name = "On Repeat"
        library.favorites.append(song("B", plays: 30))
        try await sort()

        #expect(library.playlists.map(\.name) == ["Heavy Rotation · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Heavy Rotation · Sorted") == ["A", "B"])
        #expect(rule.currentSortedPlaylist?.name == "Heavy Rotation · Sorted")
    }

    // MARK: Tightening

    @Test(arguments: [
        // Raising the play count.
        ([Condition.playCountAtLeast(5)], [Condition.playCountAtLeast(10)]),
        // Adding a Condition.
        ([.playCountAtLeast(5)], [.playCountAtLeast(5), .genreIs("Jazz")]),
        // Replacing a Condition with a different one.
        ([.genreIs("Jazz")], [.genreIs("Rock")]),
        // Narrowing a decade to a year.
        ([.releasedInDecade(1990)], [.releasedInYear(1995)]),
        // Narrowing any Song to some Songs.
        ([], [.sourcePlaylistIs(.myShazamTracks)]),
    ])
    func editsThatCanLeaveOutSongsAreTightening(old: [Condition], new: [Condition]) {
        #expect(Rule.isTightening(from: old, to: new))
    }

    @Test(arguments: [
        // Unchanged.
        ([Condition.playCountAtLeast(5)], [Condition.playCountAtLeast(5)]),
        // Lowering the play count.
        ([.playCountAtLeast(10)], [.playCountAtLeast(5)]),
        // Removing a Condition.
        ([.playCountAtLeast(5), .genreIs("Jazz")], [.genreIs("Jazz")]),
        // Widening a year to its decade.
        ([.releasedInYear(1995)], [.releasedInDecade(1990)]),
        // Reordering.
        ([.genreIs("Jazz"), .artistIs("Miles Davis")], [.artistIs("Miles Davis"), .genreIs("Jazz")]),
        // Same name with different case.
        ([.genreIs("Jazz")], [.genreIs("jazz")]),
    ])
    func editsThatKeepEverySongMatchingAreNotTightening(old: [Condition], new: [Condition]) {
        #expect(!Rule.isTightening(from: old, to: new))
    }

    // MARK: Start over

    @Test func startingOverCreatesANewSortedPlaylistWithAllMatchingSongs() async throws {
        library.favorites = [song("A", plays: 20), song("B", plays: 6)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(5)])
        try await sort()

        rule.conditions = [.playCountAtLeast(10)]
        rule.startOver()
        let summary = try await sort()

        #expect(library.playlists.map(\.songIDs) == [["A", "B"], ["A"]])
        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1, createdPlaylistCount: 1))
        #expect(rule.currentSortedPlaylist?.playlistID == library.playlists.last?.id)
    }

    @Test func startingOverNeverAddsToTheOldPlaylistAgain() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()
        rule.startOver()
        try await sort()

        library.favorites.append(song("B", plays: 30))
        try await sort()

        #expect(library.playlists.map(\.songIDs) == [["A"], ["A", "B"]])
    }

    @Test func startingOverUsesTheRulesCurrentName() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()

        rule.name = "On Repeat"
        rule.startOver()
        try await sort()

        #expect(library.playlists.map(\.name) == ["Heavy Rotation · Sorted", "On Repeat · Sorted"])
        #expect(rule.currentSortedPlaylist?.name == "On Repeat · Sorted")
    }

    @Test func startingOverAGroupedRuleStartsOverEveryGroupPlaylist() async throws {
        library.favorites = [song("A", plays: 1, genres: ["Jazz"]), song("B", plays: 1, genres: ["Rock"])]
        let rule = addRule("By Genre", conditions: [], grouping: .primaryGenre)
        try await sort()

        rule.startOver()
        library.favorites.append(song("C", plays: 1, genres: ["Jazz"]))
        let summary = try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted", "Rock · Sorted", "Jazz · Sorted", "Rock · Sorted"])
        #expect(library.playlists.map(\.songIDs) == [["A"], ["B"], ["A", "C"], ["B"]])
        #expect(library.appendCount == 0)
        #expect(summary == SortingRunSummary(placementCount: 3, placedIntoPlaylistCount: 2, createdPlaylistCount: 2))
        #expect(rule.groupPlaylists.map(\.songCount) == [2, 1])
    }

    @Test func startingOverAGroupedRuleAppliesTheGroupThresholdAgain() async throws {
        library.favorites = [song("A", plays: 1, genres: ["Jazz"]), song("B", plays: 1, genres: ["Jazz"])]
        let rule = addRule("By Genre", conditions: [], grouping: .primaryGenre, threshold: 2)
        try await sort()

        library.favorites = [song("A", plays: 1, genres: ["Jazz"])]
        rule.startOver()
        try await sort()

        #expect(library.playlists.count == 1)
        #expect(rule.groupPlaylists.isEmpty)
    }

    // MARK: Deleting

    @Test func deletedRuleIsNoLongerApplied() async throws {
        library.favorites = [song("A", plays: 20)]
        let rule = addRule("Heavy Rotation", conditions: [.playCountAtLeast(10)])
        try await sort()

        context.delete(rule)
        library.favorites.append(song("B", plays: 30))
        let summary = try await sort()

        #expect(library.playlists.map(\.songIDs) == [["A"]])
        #expect(summary == SortingRunSummary())
        #expect(try context.fetch(FetchDescriptor<SortedPlaylistRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Placement>()).isEmpty)
    }
}
