//
//  GroupedRuleTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Grouped Rules and Group Thresholds, driven through whole Sorting Runs over the fake
/// library and an in-memory store.
@MainActor
struct GroupedRuleTests {
    let library = FakeMusicLibrary()
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Schema(MusicSorterSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var context: ModelContext { container.mainContext }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @discardableResult
    private func addRule(
        _ name: String,
        groupedBy grouping: Grouping,
        threshold: Int = 1,
        conditions: [Condition] = []
    ) throws -> Rule {
        let rule = Rule(
            name: name,
            conditions: conditions,
            grouping: grouping,
            groupThreshold: threshold,
            createdAt: try date(2026, 1, 1)
        )
        context.insert(rule)
        return rule
    }

    @discardableResult
    private func sort(at now: Date? = nil) async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: now ?? date(2026, 6, 1))
    }

    private func song(
        _ id: String,
        plays: Int? = 1,
        genres: [String] = [],
        firstArtist: String? = nil,
        released: String? = nil
    ) throws -> LibrarySong {
        LibrarySong(
            id: id,
            title: "Song \(id)",
            playCount: plays,
            genres: genres,
            firstArtistName: firstArtist,
            releaseDate: try released.map { try Date("\($0)T00:00:00Z", strategy: .iso8601) }
        )
    }

    private func songs(_ ids: [String], genres: [String]) throws -> [LibrarySong] {
        try ids.map { try song($0, genres: genres) }
    }

    // MARK: Group Threshold

    @Test func groupBelowItsThresholdHasNoSortedPlaylist() async throws {
        library.favorites = try songs(["A", "B", "C", "D"], genres: ["Jazz"])
        try addRule("By Genre", groupedBy: .primaryGenre, threshold: 5)

        let summary = try await sort()

        #expect(library.playlists.isEmpty)
        #expect(summary == SortingRunSummary())
    }

    @Test func groupReachingItsThresholdGetsItsPlaylistWithAllItsSongsAtOnce() async throws {
        library.favorites = try songs(["A", "B", "C", "D"], genres: ["Jazz"])
        try addRule("By Genre", groupedBy: .primaryGenre, threshold: 5)
        try await sort()

        library.favorites.append(try song("E", genres: ["Jazz"]))
        let summary = try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A", "B", "C", "D", "E"])
        #expect(library.appendCount == 0)
        #expect(summary == SortingRunSummary(placementCount: 5, placedIntoPlaylistCount: 1, createdPlaylistCount: 1))
    }

    @Test func songsJoiningAnExistingGroupAreAppended() async throws {
        library.favorites = try songs(["A", "B"], genres: ["Jazz"])
        try addRule("By Genre", groupedBy: .primaryGenre, threshold: 2)
        try await sort()

        library.favorites.append(try song("C", genres: ["Jazz"]))
        let summary = try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A", "B", "C"])
        #expect(library.appendCount == 1)
        #expect(summary == SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1))
    }

    @Test func groupPlaylistStaysOnceCreatedEvenIfTheGroupShrinks() async throws {
        library.favorites = try songs(["A", "B"], genres: ["Jazz"])
        try addRule("By Genre", groupedBy: .primaryGenre, threshold: 2)
        try await sort()

        library.favorites = [try song("C", genres: ["Jazz"])]
        try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A", "B", "C"])
    }

    @Test func eachGroupReachesItsThresholdOnItsOwn() async throws {
        library.favorites = try songs(["A", "B"], genres: ["Jazz"]) + songs(["C"], genres: ["Rock"])
        try addRule("By Genre", groupedBy: .primaryGenre, threshold: 2)

        try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted"])
    }

    @Test func newRuleDefaultsToAGroupThresholdOfFive() {
        let rule = Rule(name: "By Genre", conditions: [], grouping: .primaryGenre, createdAt: .now)

        #expect(rule.groupThreshold == 5)
    }

    // MARK: Grouping attributes

    @Test func primaryGenrePutsEachSongIntoExactlyOneGroup() async throws {
        library.favorites = [
            try song("A", genres: ["Music", "Jazz", "Bebop"]),
            try song("B", genres: ["Rock", "Music"]),
            try song("C", genres: ["Jazz", "Rock"]),
        ]
        try addRule("By Genre", groupedBy: .primaryGenre)

        try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted", "Rock · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A", "C"])
        #expect(library.songIDs(inPlaylistNamed: "Rock · Sorted") == ["B"])
    }

    @Test func artistGroupsByTheFirstLinkedArtist() async throws {
        library.favorites = [
            LibrarySong(id: "A", title: "Song A", artistName: "Daft Punk & Pharrell Williams", firstArtistName: "Daft Punk"),
            LibrarySong(id: "B", title: "Song B", artistName: "Daft Punk", firstArtistName: "Daft Punk"),
            LibrarySong(id: "C", title: "Song C", artistName: "Pharrell Williams", firstArtistName: "Pharrell Williams"),
        ]
        try addRule("By Artist", groupedBy: .artist)

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Daft Punk · Sorted") == ["A", "B"])
        #expect(library.songIDs(inPlaylistNamed: "Pharrell Williams · Sorted") == ["C"])
    }

    @Test func releaseDecadeGroupsBySongsDecade() async throws {
        library.favorites = [
            try song("A", released: "1990-01-01"),
            try song("B", released: "1999-12-31"),
            try song("C", released: "2000-01-01"),
        ]
        try addRule("By Decade", groupedBy: .releaseDecade)

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "1990s · Sorted") == ["A", "B"])
        #expect(library.songIDs(inPlaylistNamed: "2000s · Sorted") == ["C"])
    }

    @Test func firstSeenYearGroupsBySongsFirstSeenYear() async throws {
        library.favorites = [try song("A")]
        try await sort(at: try date(2025, 6, 1))
        library.favorites.append(try song("B"))
        try await sort(at: try date(2026, 6, 1))

        try addRule("By Year", groupedBy: .firstSeenYear(in: nil))
        try await sort(at: try date(2026, 7, 1))

        #expect(library.songIDs(inPlaylistNamed: "2025 · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "2026 · Sorted") == ["B"])
    }

    @Test func firstSeenYearForASourcePlaylistUsesThatSourcesFirstSeen() async throws {
        // A was favorited in 2025 and Shazamed in 2026.
        library.favorites = [try song("A")]
        try await sort(at: try date(2025, 6, 1))
        library.shazamSongs = [try song("A")]
        try await sort(at: try date(2026, 6, 1))

        try addRule("Shazamed By Year", groupedBy: .firstSeenYear(in: .myShazamTracks))
        try addRule("Seen By Year", groupedBy: .firstSeenYear(in: nil))
        try await sort(at: try date(2026, 7, 1))

        let shazamed = try #require(context.fetch(FetchDescriptor<Rule>()).first { $0.name == "Shazamed By Year" })
        let seen = try #require(context.fetch(FetchDescriptor<Rule>()).first { $0.name == "Seen By Year" })
        #expect(shazamed.sortedPlaylists?.map(\.groupValue) == ["2026"])
        #expect(seen.sortedPlaylists?.map(\.groupValue) == ["2025"])
    }

    @Test func firstSeenYearIsReadInTheTimeZoneTheRuleWasMadeIn() async throws {
        // Midnight-thirty on New Year's Day in UTC is still New Year's Eve in Los Angeles.
        library.favorites = [try song("A")]
        try await sort(at: try Date("2026-01-01T00:30:00Z", strategy: .iso8601))

        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        try addRule("By Year in LA", groupedBy: .firstSeenYear(in: nil, timeZone: losAngeles))
        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "2025 · Sorted") == ["A"])
    }

    // MARK: Missing values and Conditions

    @Test func songsMissingTheGroupingValueAreLeftOut() async throws {
        library.favorites = [
            try song("A", genres: ["Jazz"]),
            try song("B", genres: []),
            try song("C", genres: ["Music"]),
            try song("D"),
        ]
        try addRule("By Genre", groupedBy: .primaryGenre)
        try addRule("By Artist", groupedBy: .artist)
        try addRule("By Decade", groupedBy: .releaseDecade)

        try await sort()

        #expect(library.playlists.map(\.name) == ["Jazz · Sorted"])
        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A"])
    }

    @Test func conditionsNarrowWhichSongsAreGrouped() async throws {
        library.favorites = [
            try song("A", plays: 20, genres: ["Jazz"]),
            try song("B", plays: 2, genres: ["Jazz"]),
            try song("C", plays: 30, genres: ["Rock"]),
            try song("D", plays: 1, genres: ["Rock"]),
        ]
        try addRule("Loved By Genre", groupedBy: .primaryGenre, conditions: [.playCountAtLeast(10)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "Rock · Sorted") == ["C"])
    }

    @Test func groupThresholdCountsOnlySongsMeetingTheConditions() async throws {
        library.favorites = [
            try song("A", plays: 20, genres: ["Jazz"]),
            try song("B", plays: 2, genres: ["Jazz"]),
        ]
        try addRule("Loved By Genre", groupedBy: .primaryGenre, threshold: 2, conditions: [.playCountAtLeast(10)])

        try await sort()

        #expect(library.playlists.isEmpty)
    }

    @Test func groupedRuleRecordsEachGroupsPlaylistAndSongCount() async throws {
        library.favorites = try songs(["A", "B"], genres: ["Jazz"]) + songs(["C"], genres: ["Rock"])
        let rule = try addRule("By Genre", groupedBy: .primaryGenre)

        try await sort()

        let groups = rule.groupPlaylists.map { ($0.name, $0.songCount) }
        #expect(groups.map(\.0) == ["Jazz · Sorted", "Rock · Sorted"])
        #expect(groups.map(\.1) == [2, 1])
    }

    @Test func groupingRoundTripsThroughItsStoredEncoding() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for grouping: Grouping in [.primaryGenre, .artist, .releaseDecade, .firstSeenYear(in: .myShazamTracks, timeZone: losAngeles)] {
            let rule = Rule(name: "Grouped", conditions: [], grouping: grouping, createdAt: .now)
            #expect(rule.grouping == grouping)
        }
    }
}
