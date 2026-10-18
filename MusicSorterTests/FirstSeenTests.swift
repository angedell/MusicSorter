//
//  FirstSeenTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// First Seen recording and the First Seen Condition, driven through whole Sorting Runs
/// over the fake library and an in-memory store, with the time of each run injected.
@MainActor
struct FirstSeenTests {
    let library = FakeMusicLibrary()
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Schema(MusicSorterSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var context: ModelContext { container.mainContext }

    /// First Seen years and days are read in the device's calendar, so test times are
    /// built in it too.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func addRule(_ name: String, conditions: [Condition], createdAt: Date) {
        context.insert(Rule(name: name, conditions: conditions, createdAt: createdAt))
    }

    @discardableResult
    private func sort(at now: Date) async throws -> SortingRunSummary {
        try await SortingEngine(gateway: library, modelContext: context).run(now: now)
    }

    private func song(_ id: String) -> LibrarySong {
        LibrarySong(id: id, title: "Song \(id)", playCount: 1)
    }

    /// A First Seen Condition for a single day.
    private func firstSeen(on day: Date, in source: SourcePlaylist?) -> Condition {
        .firstSeen(.between(firstDay: day, lastDay: day), in: source)
    }

    @Test func runRecordsFirstSeenForEachSongAndSourcePlaylistUsingTheRunsTime() async throws {
        let march1 = try date(2026, 3, 1)
        library.favorites = [song("A"), song("B")]
        library.shazamSongs = [song("B")]
        try await sort(at: march1)

        addRule("Favorited March 1", conditions: [firstSeen(on: march1, in: .favoriteSongs)], createdAt: try date(2026, 7, 1))
        addRule("Shazamed March 1", conditions: [firstSeen(on: march1, in: .myShazamTracks)], createdAt: try date(2026, 7, 1))
        try await sort(at: try date(2026, 7, 1))

        #expect(library.songIDs(inPlaylistNamed: "Favorited March 1 · Sorted") == ["A", "B"])
        #expect(library.songIDs(inPlaylistNamed: "Shazamed March 1 · Sorted") == ["B"])
    }

    @Test func laterRunsRecordOnlyNewPairsAndKeepTheOriginalFirstSeen() async throws {
        let march1 = try date(2026, 3, 1)
        let july1 = try date(2026, 7, 1)
        library.favorites = [song("A")]
        try await sort(at: march1)
        library.favorites = [song("A"), song("B")]
        library.shazamSongs = [song("A")]
        try await sort(at: july1)

        addRule("Favorited March 1", conditions: [firstSeen(on: march1, in: .favoriteSongs)], createdAt: try date(2026, 8, 1))
        addRule("Favorited July 1", conditions: [firstSeen(on: july1, in: .favoriteSongs)], createdAt: try date(2026, 8, 1))
        addRule("Shazamed July 1", conditions: [firstSeen(on: july1, in: .myShazamTracks)], createdAt: try date(2026, 8, 1))
        try await sort(at: try date(2026, 8, 1))

        #expect(library.songIDs(inPlaylistNamed: "Favorited March 1 · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "Favorited July 1 · Sorted") == ["B"])
        #expect(library.songIDs(inPlaylistNamed: "Shazamed July 1 · Sorted") == ["A"])
    }

    @Test func firstSeenIsKeptWhenTheRunIsInterrupted() async throws {
        library.favorites = [song("A")]
        addRule("Everything", conditions: [.playCountAtLeast(0)], createdAt: try date(2026, 3, 1))
        try await sort(at: try date(2026, 3, 1))

        library.favorites.append(song("B"))
        library.appendsBeforeFailure = 0
        await #expect(throws: FakeMusicLibrary.FakeError.interrupted) {
            try await sort(at: try date(2026, 12, 31))
        }

        // A fresh context sees only what the interrupted run saved, as after a relaunch.
        let relaunched = ModelContext(container)
        relaunched.insert(Rule(name: "2026", conditions: [.firstSeen(.year(2026), in: nil)], createdAt: try date(2027, 1, 2)))
        try await SortingEngine(gateway: library, modelContext: relaunched).run(now: try date(2027, 1, 2))

        #expect(library.songIDs(inPlaylistNamed: "2026 · Sorted") == ["A", "B"])
    }

    @Test func firstSeenPeriodIsReadInTheTimeZoneItWasMadeIn() async throws {
        // Midnight-thirty on New Year's Day in UTC is still New Year's Eve in Los Angeles.
        library.favorites = [song("A")]
        try await sort(at: try Date("2026-01-01T00:30:00Z", strategy: .iso8601))

        let utc = TimeZone.gmt
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        addRule("2026 in UTC", conditions: [.firstSeen(.year(2026, in: utc), in: nil)], createdAt: try date(2026, 6, 1))
        addRule("2025 in LA", conditions: [.firstSeen(.year(2025, in: losAngeles), in: nil)], createdAt: try date(2026, 6, 1))
        try await sort(at: try date(2026, 6, 1))

        // Each Condition reads the year in its own time zone, whatever the device's is.
        #expect(library.songIDs(inPlaylistNamed: "2026 in UTC · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "2025 in LA · Sorted") == ["A"])
    }

    @Test func songThatLeavesAndComesBackKeepsItsOriginalFirstSeen() async throws {
        library.shazamSongs = [song("A")]
        try await sort(at: try date(2026, 3, 1))
        library.shazamSongs = []
        try await sort(at: try date(2026, 9, 1))

        library.shazamSongs = [song("A")]
        addRule("Shazamed 2026", conditions: [.firstSeen(.year(2026), in: .myShazamTracks)], createdAt: try date(2027, 2, 1))
        addRule("Shazamed 2027", conditions: [.firstSeen(.year(2027), in: .myShazamTracks)], createdAt: try date(2027, 2, 1))
        try await sort(at: try date(2027, 2, 1))

        #expect(library.songIDs(inPlaylistNamed: "Shazamed 2026 · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "Shazamed 2027 · Sorted") == [])
    }

    @Test func firstSeenYearConditionMatchesSongsFirstSeenThatYear() async throws {
        library.shazamSongs = [song("LastMomentBefore")]
        try await sort(at: try date(2025, 12, 31, hour: 23))
        library.shazamSongs.append(song("FirstDay"))
        try await sort(at: try date(2026, 1, 1, hour: 0))
        library.shazamSongs.append(song("LastDay"))
        try await sort(at: try date(2026, 12, 31, hour: 23))

        library.shazamSongs.append(song("NextYear"))
        addRule("2026", conditions: [.firstSeen(.year(2026), in: nil)], createdAt: try date(2027, 1, 1))
        try await sort(at: try date(2027, 1, 1, hour: 0))

        #expect(library.songIDs(inPlaylistNamed: "2026 · Sorted") == ["FirstDay", "LastDay"])
    }

    @Test func firstSeenBetweenDatesConditionIncludesBothDays() async throws {
        library.shazamSongs = [song("DayBefore")]
        try await sort(at: try date(2026, 5, 31, hour: 23))
        library.shazamSongs.append(song("FirstDay"))
        try await sort(at: try date(2026, 6, 1, hour: 0))
        library.shazamSongs.append(song("LastDay"))
        try await sort(at: try date(2026, 8, 31, hour: 23))

        library.shazamSongs.append(song("DayAfter"))
        let summer = FirstSeenPeriod.between(firstDay: try date(2026, 6, 1), lastDay: try date(2026, 8, 31))
        addRule("Summer", conditions: [.firstSeen(summer, in: nil)], createdAt: try date(2026, 9, 1))
        try await sort(at: try date(2026, 9, 1, hour: 0))

        #expect(library.songIDs(inPlaylistNamed: "Summer · Sorted") == ["FirstDay", "LastDay"])
    }

    @Test func firstSeenConditionForASourcePlaylistUsesThatSourcesFirstSeen() async throws {
        // A was favorited in 2025 and Shazamed in 2026; B was only ever favorited.
        library.favorites = [song("A"), song("B")]
        try await sort(at: try date(2025, 6, 1))
        library.shazamSongs = [song("A")]
        try await sort(at: try date(2026, 6, 1))

        library.favorites.append(song("C"))
        addRule("Shazamed 2026", conditions: [.firstSeen(.year(2026), in: .myShazamTracks)], createdAt: try date(2026, 7, 1))
        addRule("Favorited 2026", conditions: [.firstSeen(.year(2026), in: .favoriteSongs)], createdAt: try date(2026, 7, 1))
        try await sort(at: try date(2026, 7, 1))

        #expect(library.songIDs(inPlaylistNamed: "Shazamed 2026 · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "Favorited 2026 · Sorted") == ["C"])
    }

    @Test func firstSeenConditionForAnySourceUsesTheEarliestFirstSeen() async throws {
        library.favorites = [song("A")]
        try await sort(at: try date(2025, 6, 1))
        library.shazamSongs = [song("A")]

        addRule("2025", conditions: [.firstSeen(.year(2025), in: nil)], createdAt: try date(2026, 6, 1))
        addRule("2026", conditions: [.firstSeen(.year(2026), in: nil)], createdAt: try date(2026, 6, 1))
        try await sort(at: try date(2026, 6, 1))

        #expect(library.songIDs(inPlaylistNamed: "2025 · Sorted") == ["A"])
        #expect(library.songIDs(inPlaylistNamed: "2026 · Sorted") == [])
    }

    @Test func songNeverSeenInTheConditionsSourcePlaylistFailsIt() async throws {
        library.favorites = [song("A")]
        addRule("Shazamed 2026", conditions: [.firstSeen(.year(2026), in: .myShazamTracks)], createdAt: try date(2026, 6, 1))

        try await sort(at: try date(2026, 6, 1))

        #expect(library.songIDs(inPlaylistNamed: "Shazamed 2026 · Sorted") == [])
    }

    @Test func songsFoundOnTheRulesFirstRunAreFirstSeenThen() async throws {
        library.shazamSongs = [song("A")]
        addRule("Shazamed 2026", conditions: [.firstSeen(.year(2026), in: .myShazamTracks)], createdAt: try date(2026, 6, 1))

        try await sort(at: try date(2026, 6, 1))

        #expect(library.songIDs(inPlaylistNamed: "Shazamed 2026 · Sorted") == ["A"])
    }

    @Test func firstSeenConditionsRoundTripThroughTheirStoredEncoding() throws {
        let conditions: [Condition] = [
            .firstSeen(.year(2026), in: .myShazamTracks),
            .firstSeen(.between(firstDay: try date(2026, 6, 1), lastDay: try date(2026, 8, 31)), in: nil),
        ]
        let rule = Rule(name: "First Seen", conditions: conditions, createdAt: try date(2026, 6, 1))

        #expect(rule.storedConditions == conditions)
    }
}
