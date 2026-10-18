//
//  SortingEngine.swift
//  MusicSorter
//

import Foundation
import SwiftData

/// What a Sorting Run did.
struct SortingRunSummary: Equatable {
    var placementCount: Int = 0
    var createdPlaylistCount: Int = 0
}

/// Runs Sorting Runs: reads the Source Playlists, applies every active Rule and records
/// new Placements.
struct SortingEngine {
    let gateway: any MusicLibraryGateway
    let modelContext: ModelContext

    func run(now: Date) async throws -> SortingRunSummary {
        var summary = SortingRunSummary()
        let songs = try await currentSongs()

        let rules = try modelContext.fetch(FetchDescriptor<Rule>(sortBy: [SortDescriptor(\.createdAt)]))
        for rule in rules where rule.status == .active {
            let matchingSongIDs = songs.filter { rule.isMet(by: $0) }.map(\.id)

            guard let record = rule.currentSortedPlaylist else {
                // A new Sorted Playlist is created already holding its Songs: one MusicKit
                // call instead of one slow add per Song.
                let playlistID = try await gateway.createPlaylist(
                    named: rule.sortedPlaylistName,
                    songIDs: matchingSongIDs
                )
                let record = SortedPlaylistRecord(rule: rule, playlistID: playlistID, createdAt: now)
                modelContext.insert(record)
                for songID in matchingSongIDs {
                    modelContext.insert(Placement(sortedPlaylist: record, songID: songID, placedAt: now))
                }
                try modelContext.save()
                summary.createdPlaylistCount += 1
                summary.placementCount += matchingSongIDs.count
                continue
            }

            let alreadyPlaced = Set((record.placements ?? []).map(\.songID))
            // Each Placement is written right after its add succeeds, so an interrupted run
            // resumes without duplicates.
            for songID in matchingSongIDs where !alreadyPlaced.contains(songID) {
                try await gateway.append(songID: songID, toPlaylistWithID: record.playlistID)
                modelContext.insert(Placement(sortedPlaylist: record, songID: songID, placedAt: now))
                try modelContext.save()
                summary.placementCount += 1
            }
        }

        try AppState.current(in: modelContext).lastSortingRunAt = now
        try modelContext.save()
        return summary
    }

    /// The Songs of every Source Playlist, each Song once, in first-seen order.
    private func currentSongs() async throws -> [LibrarySong] {
        var seen = Set<String>()
        var songs: [LibrarySong] = []
        for source in SourcePlaylist.allCases {
            for song in try await gateway.songs(in: source) ?? [] where seen.insert(song.id).inserted {
                songs.append(song)
            }
        }
        return songs
    }
}
