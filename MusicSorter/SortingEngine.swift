//
//  SortingEngine.swift
//  MusicSorter
//

import Foundation
import SwiftData

/// Something the user should know about a Sorting Run that still completed.
enum SortingRunWarning: Equatable {
    /// "My Shazam Tracks" doesn't exist, so only Favorite Songs were sorted.
    case shazamPlaylistMissing
}

/// What a Sorting Run did.
struct SortingRunSummary: Equatable {
    var placementCount: Int = 0
    var createdPlaylistCount: Int = 0
    var warnings: [SortingRunWarning] = []
}

/// Runs Sorting Runs: reads the Source Playlists, applies every active Rule and records
/// new Placements.
struct SortingEngine {
    let gateway: any MusicLibraryGateway
    let modelContext: ModelContext

    func run(now: Date) async throws -> SortingRunSummary {
        var summary = SortingRunSummary()
        let (songs, missingSources) = try await currentSongs()
        if missingSources.contains(.myShazamTracks) {
            summary.warnings.append(.shazamPlaylistMissing)
        }

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

        let state = try AppState.current(in: modelContext)
        state.lastSortingRunAt = now
        state.isShazamPlaylistMissing = summary.warnings.contains(.shazamPlaylistMissing)
        try modelContext.save()
        return summary
    }

    /// The Songs of every Source Playlist, each Song once (by catalog ID) in first-seen
    /// order and carrying every Source Playlist it was found in, plus the Source Playlists
    /// that don't exist.
    private func currentSongs() async throws -> (songs: [LibrarySong], missing: Set<SourcePlaylist>) {
        var indexByID: [String: Int] = [:]
        var songs: [LibrarySong] = []
        var missing = Set<SourcePlaylist>()
        for source in SourcePlaylist.allCases {
            guard let sourceSongs = try await gateway.songs(in: source) else {
                missing.insert(source)
                continue
            }
            for song in sourceSongs {
                if let index = indexByID[song.id] {
                    songs[index].sources.insert(source)
                } else {
                    indexByID[song.id] = songs.count
                    var song = song
                    song.sources = [source]
                    songs.append(song)
                }
            }
        }
        return (songs, missing)
    }
}
