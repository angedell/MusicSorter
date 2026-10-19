//
//  Models.swift
//  MusicSorter
//

import Foundation
import SwiftData

/// A user-defined set of Conditions, all of which a Song must meet to be placed into the
/// Rule's Sorted Playlist or, for a Grouped Rule, into its Group's Sorted Playlist.
///
/// Properties are defaulted and relationships optional to stay compatible with CloudKit.
@Model
final class Rule {
    enum Status: String, Codable {
        case active
        case paused
    }

    var name: String = ""
    var createdAt: Date = Date.distantPast
    var statusRawValue: String = Status.active.rawValue
    /// Conditions are stored JSON-encoded so the enum's associated values survive persistence.
    var conditionsData: Data = Data()
    /// The JSON-encoded Grouping, or `nil` for a Rule that isn't grouped.
    var groupingData: Data?
    /// How many Songs a Group needs before its Sorted Playlist is created.
    var groupThreshold: Int = 5

    @Relationship(deleteRule: .cascade, inverse: \SortedPlaylistRecord.rule)
    var sortedPlaylists: [SortedPlaylistRecord]? = []

    init(
        name: String,
        conditions: [Condition],
        grouping: Grouping? = nil,
        groupThreshold: Int = 5,
        createdAt: Date
    ) {
        self.name = name
        self.createdAt = createdAt
        self.conditions = conditions
        if let grouping {
            self.groupingData = try? JSONEncoder().encode(grouping)
        }
        self.groupThreshold = groupThreshold
    }

    var status: Status {
        get { Status(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var conditions: [Condition] {
        get { storedConditions ?? [] }
        set { conditionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// The decoded Conditions, or `nil` if the stored data can't be read.
    var storedConditions: [Condition]? {
        try? JSONDecoder().decode([Condition].self, from: conditionsData)
    }

    var isGrouped: Bool { groupingData != nil }

    /// The decoded Grouping, or `nil` if the Rule isn't grouped or the stored data can't
    /// be read.
    var grouping: Grouping? {
        guard let groupingData else { return nil }
        return try? JSONDecoder().decode(Grouping.self, from: groupingData)
    }

    /// The name a Sorted Playlist is created with, given the Rule's name or, for a Grouped
    /// Rule, the Group's value.
    static func sortedPlaylistName(for ruleNameOrGroupValue: String) -> String {
        "\(ruleNameOrGroupValue) · Sorted"
    }

    var sortedPlaylistName: String { Self.sortedPlaylistName(for: name) }

    /// The Sorted Playlists the Rule still places Songs into: every one created since the
    /// Rule last started over.
    var attachedSortedPlaylists: [SortedPlaylistRecord] {
        (sortedPlaylists ?? []).filter { !$0.isDetached }
    }

    /// The Sorted Playlist the Rule currently places Songs into, if it has one yet.
    var currentSortedPlaylist: SortedPlaylistRecord? {
        attachedSortedPlaylists.max(by: { $0.createdAt < $1.createdAt })
    }

    /// A Grouped Rule's Group playlists created since it last started over, by name.
    var groupPlaylists: [SortedPlaylistRecord] {
        attachedSortedPlaylists
            .filter { $0.groupValue != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether the Rule has a Sorted Playlist it could start over from. A Paused Rule is
    /// resumed instead.
    var canStartOver: Bool { status == .active && !attachedSortedPlaylists.isEmpty }

    /// Detaches every Sorted Playlist of the Rule, so the next Sorting Run creates new ones
    /// holding every Song that meets the Rule then. The old playlists stay in Music, but the
    /// app never adds to them again.
    func startOver() {
        for playlist in attachedSortedPlaylists {
            playlist.isDetached = true
        }
    }

    /// The Sorted Playlists the user deleted in the Music app, which paused the Rule.
    var deletedSortedPlaylists: [SortedPlaylistRecord] {
        attachedSortedPlaylists
            .filter(\.isDeletedInMusic)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Pauses the Rule because the user deleted the given Sorted Playlists in the Music app.
    func pause(deleted playlists: [SortedPlaylistRecord]) {
        for playlist in playlists {
            playlist.isDeletedInMusic = true
        }
        status = .paused
    }

    /// Applies a Paused Rule again. Its deleted Sorted Playlists are detached, so the next
    /// Sorting Run creates new ones holding every Song that meets the Rule then; a Grouped
    /// Rule's other Group playlists carry on as before.
    func resume() {
        for playlist in deletedSortedPlaylists {
            playlist.isDetached = true
        }
        status = .active
    }

    /// Whether changing the Rule's Conditions from `old` to `new` could leave out a Song
    /// that met `old`. Such a Song stays in the Sorted Playlist (ADR 0001), so the user is
    /// warned. Errs towards warning: an edit counts as tightening unless every new
    /// Condition is implied by an old one.
    static func isTightening(from old: [Condition], to new: [Condition]) -> Bool {
        !new.allSatisfy { condition in old.contains { $0.implies(condition) } }
    }
}

/// The app's record of a Sorted Playlist it created in Apple Music. The playlist is
/// referred to only by its ID, so renaming it in Music doesn't matter.
@Model
final class SortedPlaylistRecord {
    var rule: Rule?
    var playlistID: String = ""
    /// The name the playlist was created with. Renaming the Rule doesn't rename it.
    /// Empty for playlists recorded before the name was stored.
    var createdName: String = ""
    var createdAt: Date = Date.distantPast
    /// The Group this playlist holds, for a Grouped Rule; `nil` otherwise.
    var groupValue: String?
    /// Set when the Rule starts over: the app never adds to the playlist again.
    var isDetached: Bool = false
    /// Set when a Sorting Run finds the user deleted the playlist in the Music app.
    var isDeletedInMusic: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Placement.sortedPlaylist)
    var placements: [Placement]? = []

    init(rule: Rule, playlistID: String, name: String, groupValue: String? = nil, createdAt: Date) {
        self.rule = rule
        self.playlistID = playlistID
        self.createdName = name
        self.groupValue = groupValue
        self.createdAt = createdAt
    }

    /// The name the playlist was created with.
    var name: String {
        createdName.isEmpty ? Rule.sortedPlaylistName(for: groupValue ?? rule?.name ?? "") : createdName
    }

    /// How many Songs the app has placed into this Sorted Playlist.
    var songCount: Int { placements?.count ?? 0 }
}

/// The permanent record that the app added a Song to a Sorted Playlist.
/// A Song is never placed into the same Sorted Playlist twice.
@Model
final class Placement {
    var sortedPlaylist: SortedPlaylistRecord?
    var songID: String = ""
    var placedAt: Date = Date.distantPast

    init(sortedPlaylist: SortedPlaylistRecord, songID: String, placedAt: Date) {
        self.sortedPlaylist = sortedPlaylist
        self.songID = songID
        self.placedAt = placedAt
    }
}

/// The moment the app first found a Song in a Source Playlist. Recorded once per Song and
/// Source Playlist and never changed, even if the Song leaves the playlist and comes back.
@Model
final class FirstSeen {
    var songID: String = ""
    var sourceRawValue: String = ""
    var firstSeenAt: Date = Date.distantPast

    init(songID: String, source: SourcePlaylist, firstSeenAt: Date) {
        self.songID = songID
        self.sourceRawValue = source.rawValue
        self.firstSeenAt = firstSeenAt
    }

    /// `nil` if the stored Source Playlist isn't one this version of the app knows.
    var source: SourcePlaylist? { SourcePlaylist(rawValue: sourceRawValue) }
}

/// App-wide state; there is at most one instance.
@Model
final class AppState {
    var lastSortingRunAt: Date?
    /// Whether the last Sorting Run found no "My Shazam Tracks" playlist. The app shows
    /// how to turn on "Sync to Apple Music" in Shazam while this is set.
    var isShazamPlaylistMissing: Bool = false

    init(lastSortingRunAt: Date? = nil) {
        self.lastSortingRunAt = lastSortingRunAt
    }

    /// The stored AppState, inserted on first use.
    static func current(in context: ModelContext) throws -> AppState {
        if let existing = try context.fetch(FetchDescriptor<AppState>()).first {
            return existing
        }
        let state = AppState()
        context.insert(state)
        return state
    }
}

enum MusicSorterSchema {
    static let models: [any PersistentModel.Type] = [
        Rule.self,
        SortedPlaylistRecord.self,
        Placement.self,
        FirstSeen.self,
        AppState.self,
    ]
}
