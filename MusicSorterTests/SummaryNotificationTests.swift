//
//  SummaryNotificationTests.swift
//  MusicSorterTests
//

import Testing
@testable import MusicSorter

/// The message of the optional notification posted after a background Sorting Run.
struct SummaryNotificationTests {
    @Test func runThatPlacedNothingHasNoMessage() {
        #expect(SummaryNotification.message(for: SortingRunSummary()) == nil)
        // A new Sorted Playlist with no Songs isn't news.
        #expect(SummaryNotification.message(for: SortingRunSummary(createdPlaylistCount: 1)) == nil)
    }

    @Test func messageCountsSongsAndPlaylists() {
        let summary = SortingRunSummary(placementCount: 6, placedIntoPlaylistCount: 3, createdPlaylistCount: 1)

        #expect(SummaryNotification.message(for: summary) == "Placed 6 songs into 3 playlists.")
    }

    @Test func messageUsesSingularsForOne() {
        let summary = SortingRunSummary(placementCount: 1, placedIntoPlaylistCount: 1)

        #expect(SummaryNotification.message(for: summary) == "Placed 1 song into 1 playlist.")
    }

    @Test func messageMixesSingularAndPlural() {
        let summary = SortingRunSummary(placementCount: 4, placedIntoPlaylistCount: 1)

        #expect(SummaryNotification.message(for: summary) == "Placed 4 songs into 1 playlist.")
    }
}
