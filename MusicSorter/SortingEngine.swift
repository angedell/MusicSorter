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
    /// The Rule with this name became a Paused Rule because one of its Sorted Playlists
    /// was deleted in the Music app.
    case rulePaused(String)
}

/// What a Sorting Run did.
struct SortingRunSummary: Equatable {
    var placementCount: Int = 0
    /// The Sorted Playlists that received at least one Placement.
    var placedIntoPlaylistCount: Int = 0
    var createdPlaylistCount: Int = 0
    var warnings: [SortingRunWarning] = []
}

/// Runs Sorting Runs: reads the Source Playlists, applies every active Rule and records
/// new Placements.
///
/// A run may stop part-way: an add can fail, or the run's task can be cancelled (as when
/// background time expires), which stops it before its next change to Apple Music; a change
/// already under way is let finish. Every change is recorded as soon as it succeeds, so the next run picks up where this one
/// stopped, and "Last sorted" is set only by a run that completes.
struct SortingEngine {
    let gateway: any MusicLibraryGateway
    let modelContext: ModelContext

    func run(now: Date) async throws -> SortingRunSummary {
        try Task.checkCancellation()
        var summary = SortingRunSummary()
        var (songs, missingSources) = try await currentSongs()
        try recordFirstSeen(of: &songs, now: now)
        if missingSources.contains(.myShazamTracks) {
            summary.warnings.append(.shazamPlaylistMissing)
        }

        let rules = try modelContext.fetch(FetchDescriptor<Rule>(sortBy: [SortDescriptor(\.createdAt)]))
        try await pauseRulesWithDeletedPlaylists(rules, summary: &summary)
        for rule in rules where rule.status == .active {
            let matchingSongs = songs.filter { rule.isMet(by: $0) }

            guard rule.isGrouped else {
                let matchingSongIDs = matchingSongs.map(\.id)
                if let record = rule.currentSortedPlaylist {
                    try await append(matchingSongIDs, to: record, now: now, summary: &summary)
                } else {
                    try await createSortedPlaylist(for: rule, groupValue: nil, songIDs: matchingSongIDs, now: now, summary: &summary)
                }
                continue
            }
            // A Grouping that can't be read can't be applied, so the Rule places nothing.
            guard let grouping = rule.grouping else { continue }

            for (groupValue, songIDs) in Self.groups(of: matchingSongs, by: grouping) {
                if let record = rule.attachedSortedPlaylists.first(where: { $0.groupValue == groupValue }) {
                    try await append(songIDs, to: record, now: now, summary: &summary)
                } else if songIDs.count >= rule.groupThreshold {
                    // The Group's Songs are all placed at once when it reaches the Group
                    // Threshold; below it, the Group has no Sorted Playlist.
                    try await createSortedPlaylist(for: rule, groupValue: groupValue, songIDs: songIDs, now: now, summary: &summary)
                }
            }
        }

        let state = try AppState.current(in: modelContext)
        state.lastSortingRunAt = now
        state.isShazamPlaylistMissing = summary.warnings.contains(.shazamPlaylistMissing)
        try modelContext.save()
        return summary
    }

    /// Pauses every active Rule one of whose Sorted Playlists the user deleted in the Music
    /// app; the app never recreates it on its own. Detached playlists aren't checked, since
    /// the app no longer adds to them.
    private func pauseRulesWithDeletedPlaylists(_ rules: [Rule], summary: inout SortingRunSummary) async throws {
        let activeRules = rules.filter { $0.status == .active }
        let playlistIDs = Set(activeRules.flatMap { $0.attachedSortedPlaylists.map(\.playlistID) })
        guard !playlistIDs.isEmpty else { return }
        let existing = try await gateway.existingPlaylistIDs(among: playlistIDs)
        guard existing != playlistIDs else { return }
        for rule in activeRules {
            let deleted = rule.attachedSortedPlaylists.filter { !existing.contains($0.playlistID) }
            guard !deleted.isEmpty else { continue }
            rule.pause(deleted: deleted)
            summary.warnings.append(.rulePaused(rule.name))
        }
        try modelContext.save()
    }

    /// Creates a Sorted Playlist already holding its Songs (one MusicKit call instead of
    /// one slow add per Song) and records their Placements.
    private func createSortedPlaylist(
        for rule: Rule,
        groupValue: String?,
        songIDs: [String],
        now: Date,
        summary: inout SortingRunSummary
    ) async throws {
        let name = Rule.sortedPlaylistName(for: groupValue ?? rule.name)
        let playlistID = try await uncancellable { try await gateway.createPlaylist(named: name, songIDs: songIDs) }
        let record = SortedPlaylistRecord(rule: rule, playlistID: playlistID, name: name, groupValue: groupValue, createdAt: now)
        modelContext.insert(record)
        for songID in songIDs {
            modelContext.insert(Placement(sortedPlaylist: record, songID: songID, placedAt: now))
        }
        try modelContext.save()
        summary.createdPlaylistCount += 1
        summary.placementCount += songIDs.count
        if !songIDs.isEmpty {
            summary.placedIntoPlaylistCount += 1
        }
    }

    /// Appends the Songs not yet placed in the Sorted Playlist. Each Placement is written
    /// right after its add succeeds, so an interrupted run resumes without duplicates.
    private func append(
        _ songIDs: [String],
        to record: SortedPlaylistRecord,
        now: Date,
        summary: inout SortingRunSummary
    ) async throws {
        let alreadyPlaced = Set((record.placements ?? []).map(\.songID))
        let newSongIDs = songIDs.filter { !alreadyPlaced.contains($0) }
        for (index, songID) in newSongIDs.enumerated() {
            try await uncancellable { try await gateway.append(songID: songID, toPlaylistWithID: record.playlistID) }
            modelContext.insert(Placement(sortedPlaylist: record, songID: songID, placedAt: now))
            try modelContext.save()
            summary.placementCount += 1
            // Counted once its first Song is placed, so an interrupted run still reports it.
            if index == 0 {
                summary.placedIntoPlaylistCount += 1
            }
        }
    }

    /// Makes a change to Apple Music unless the run was cancelled. Once started, the change
    /// isn't told of a cancellation: it could reach the library yet report the cancellation,
    /// leaving it unrecorded and repeated by the next run.
    private func uncancellable<T: Sendable>(_ change: @escaping () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        // An unstructured task doesn't inherit the run's cancellation.
        return try await Task { try await change() }.value
    }

    /// The Songs' IDs by Group, Groups in the order their first Song was found. Songs
    /// missing the grouping value are left out.
    private static func groups(of songs: [LibrarySong], by grouping: Grouping) -> [(value: String, songIDs: [String])] {
        var groups: [(value: String, songIDs: [String])] = []
        var indexByValue: [String: Int] = [:]
        for song in songs {
            guard let value = grouping.value(for: song) else { continue }
            if let index = indexByValue[value] {
                groups[index].songIDs.append(song.id)
            } else {
                indexByValue[value] = groups.count
                groups.append((value, [song.id]))
            }
        }
        return groups
    }

    /// Records First Seen as `now` for each Song and Source Playlist pair not seen before,
    /// and fills in every Song's First Seen dates, including those of Source Playlists it
    /// has since left. Saved before any Rule is applied, so it survives an interrupted run.
    private func recordFirstSeen(of songs: inout [LibrarySong], now: Date) throws {
        var firstSeenBySongID: [String: [SourcePlaylist: Date]] = [:]
        for record in try modelContext.fetch(FetchDescriptor<FirstSeen>()) {
            guard let source = record.source else { continue }
            firstSeenBySongID[record.songID, default: [:]][source] = record.firstSeenAt
        }
        for index in songs.indices {
            let song = songs[index]
            var firstSeen = firstSeenBySongID[song.id] ?? [:]
            for source in song.sources where firstSeen[source] == nil {
                modelContext.insert(FirstSeen(songID: song.id, source: source, firstSeenAt: now))
                firstSeen[source] = now
            }
            songs[index].firstSeen = firstSeen
        }
        try modelContext.save()
    }

    /// The Songs of every Source Playlist, each Song once (by catalog ID) in the order
    /// found and carrying every Source Playlist it was found in, plus the Source Playlists
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
