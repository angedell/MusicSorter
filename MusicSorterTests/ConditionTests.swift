//
//  ConditionTests.swift
//  MusicSorterTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicSorter

/// Genre, artist and release Conditions, and Rules with several Conditions, driven through
/// whole Sorting Runs over the fake library and an in-memory store.
@MainActor
struct ConditionTests {
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

    private func song(
        _ id: String,
        plays: Int? = 1,
        genres: [String] = [],
        artist: String? = nil,
        released: String? = nil
    ) throws -> LibrarySong {
        LibrarySong(
            id: id,
            title: "Song \(id)",
            playCount: plays,
            genres: genres,
            artistName: artist,
            // A mistyped date fails the test rather than silently making the Song undated.
            releaseDate: try released.map { try Date($0, strategy: .iso8601.year().month().day()) }
        )
    }

    @Test func genreConditionMatchesAnyOfTheSongsGenres() async throws {
        library.favorites = [
            try song("Primary", genres: ["Jazz", "Music"]),
            try song("Secondary", genres: ["Pop", "Jazz", "Music"]),
            try song("Other", genres: ["Rock", "Music"]),
        ]
        addRule("Jazz", conditions: [.genreIs("Jazz")])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == ["Primary", "Secondary"])
    }

    @Test func genreConditionIgnoresTheCatchAllMusicGenre() async throws {
        library.favorites = [try song("A", genres: ["Jazz", "Music"]), try song("B", genres: ["Music"])]
        addRule("Music", conditions: [.genreIs("Music")])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Music · Sorted") == [])
    }

    @Test func genreConditionIgnoresCase() async throws {
        library.favorites = [try song("A", genres: ["Hip-Hop/Rap"])]
        addRule("Rap", conditions: [.genreIs("hip-hop/rap")])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Rap · Sorted") == ["A"])
    }

    @Test func songWithNoGenresFailsTheGenreCondition() async throws {
        library.favorites = [try song("NoGenres", genres: [])]
        addRule("Jazz", conditions: [.genreIs("Jazz")])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Jazz · Sorted") == [])
    }

    @Test func artistConditionMatchesSongsByThatArtist() async throws {
        library.favorites = [
            try song("A", artist: "Björk"),
            try song("B", artist: "bjork"),
            try song("C", artist: "Radiohead"),
            try song("NoArtist", artist: nil),
        ]
        addRule("Björk", conditions: [.artistIs("Björk")])

        try await sort()

        // Case and accents don't matter; a Song with no artist fails the Condition.
        #expect(library.songIDs(inPlaylistNamed: "Björk · Sorted") == ["A", "B"])
    }

    @Test func releaseYearConditionMatchesSongsReleasedThatYear() async throws {
        library.favorites = [
            try song("LastDayBefore", released: "1996-12-31"),
            try song("FirstDay", released: "1997-01-01"),
            try song("LastDay", released: "1997-12-31"),
            try song("FirstDayAfter", released: "1998-01-01"),
            try song("Undated", released: nil),
        ]
        addRule("1997", conditions: [.releasedInYear(1997)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "1997 · Sorted") == ["FirstDay", "LastDay"])
    }

    @Test func releaseDecadeConditionMatchesSongsReleasedThatDecade() async throws {
        library.favorites = [
            try song("Eighties", released: "1989-12-31"),
            try song("Start", released: "1990-01-01"),
            try song("Middle", released: "1994-06-15"),
            try song("End", released: "1999-12-31"),
            try song("TwoThousands", released: "2000-01-01"),
            try song("Undated", released: nil),
        ]
        addRule("90s", conditions: [.releasedInDecade(1990)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "90s · Sorted") == ["Start", "Middle", "End"])
    }

    @Test func ruleWithSeveralConditionsPlacesOnlySongsMeetingAllOfThem() async throws {
        library.favorites = [
            try song("All", plays: 20, genres: ["Electronic", "Music"], artist: "Björk", released: "1997-09-22"),
            try song("WrongGenre", plays: 20, genres: ["Pop", "Music"], artist: "Björk", released: "1997-09-22"),
            try song("WrongArtist", plays: 20, genres: ["Electronic", "Music"], artist: "Aphex Twin", released: "1997-09-22"),
            try song("WrongDecade", plays: 20, genres: ["Electronic", "Music"], artist: "Björk", released: "2001-08-27"),
            try song("TooFewPlays", plays: 2, genres: ["Electronic", "Music"], artist: "Björk", released: "1997-09-22"),
        ]
        addRule("Nineties Björk", conditions: [
            .genreIs("Electronic"),
            .artistIs("Björk"),
            .releasedInDecade(1990),
            .playCountAtLeast(10),
        ])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Nineties Björk · Sorted") == ["All"])
    }

    @Test func songMissingDataFailsEveryConditionThatNeedsIt() async throws {
        library.favorites = [try song("Bare", genres: [], artist: nil, released: nil)]
        addRule("Genre", conditions: [.genreIs("Jazz")])
        addRule("Artist", conditions: [.artistIs("Björk")])
        addRule("Year", conditions: [.releasedInYear(1997)])
        addRule("Decade", conditions: [.releasedInDecade(1990)])
        addRule("Favorites", conditions: [.sourcePlaylistIs(.favoriteSongs)])

        try await sort()

        #expect(library.songIDs(inPlaylistNamed: "Genre · Sorted") == [])
        #expect(library.songIDs(inPlaylistNamed: "Artist · Sorted") == [])
        #expect(library.songIDs(inPlaylistNamed: "Year · Sorted") == [])
        #expect(library.songIDs(inPlaylistNamed: "Decade · Sorted") == [])
        // Conditions that don't need the missing data are still met.
        #expect(library.songIDs(inPlaylistNamed: "Favorites · Sorted") == ["Bare"])
    }

    @Test func conditionsRoundTripThroughTheirStoredEncoding() {
        let conditions: [Condition] = [
            .genreIs("Jazz"),
            .artistIs("Björk"),
            .releasedInYear(1997),
            .releasedInDecade(1990),
        ]
        let rule = Rule(name: "All Kinds", conditions: conditions, createdAt: now)

        #expect(rule.storedConditions == conditions)
    }
}
