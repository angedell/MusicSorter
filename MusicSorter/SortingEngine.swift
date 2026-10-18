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
            let record = try await sortedPlaylist(for: rule, now: now, summary: &summary)
            let alreadyPlaced = Set((record.placements ?? []).map(\.songID))
            let newSongIDs = songs
                .filter { !alreadyPlaced.contains($0.id) && rule.isMet(by: $0) }
                .map(\.id)
            guard !newSongIDs.isEmpty else { continue }

            // Placements are written only after the add succeeds, so an interrupted run
            // resumes without duplicates.
            try await gateway.append(songIDs: newSongIDs, toPlaylistWithID: record.playlistID)
            for songID in newSongIDs {
                modelContext.insert(Placement(sortedPlaylist: record, songID: songID, placedAt: now))
            }
            try modelContext.save()
            summary.placementCount += newSongIDs.count
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

    /// The Rule's current Sorted Playlist, created in Apple Music if the Rule has none yet.
    private func sortedPlaylist(
        for rule: Rule,
        now: Date,
        summary: inout SortingRunSummary
    ) async throws -> SortedPlaylistRecord {
        if let existing = rule.sortedPlaylists?.max(by: { $0.createdAt < $1.createdAt }) {
            return existing
        }
        let playlistID = try await gateway.createPlaylist(named: "\(rule.name) · Sorted")
        let record = SortedPlaylistRecord(rule: rule, playlistID: playlistID, createdAt: now)
        modelContext.insert(record)
        // Saved straight away so a failure later in the run can't lead to a second playlist.
        try modelContext.save()
        summary.createdPlaylistCount += 1
        return record
    }
}

extension Rule {
    /// Whether the Song meets every one of the Rule's Conditions.
    func isMet(by song: LibrarySong) -> Bool {
        conditions.allSatisfy { $0.isMet(by: song) }
    }
}

extension Condition {
    func isMet(by song: LibrarySong) -> Bool {
        switch self {
        case .playCountAtLeast(let minimum):
            // Songs not in the library have no play count and count as 0 plays.
            (song.playCount ?? 0) >= minimum
        }
    }
}
