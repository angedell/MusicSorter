//
//  Models.swift
//  MusicSorter
//

import Foundation
import SwiftData

/// One test within a Rule. Only Conditions a Song can't stop meeting are allowed (ADR 0001).
enum Condition: Codable, Hashable {
    case playCountAtLeast(Int)
}

/// A user-defined set of Conditions, all of which a Song must meet to be placed into the
/// Rule's Sorted Playlist.
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

    @Relationship(deleteRule: .cascade, inverse: \SortedPlaylistRecord.rule)
    var sortedPlaylists: [SortedPlaylistRecord]? = []

    init(name: String, conditions: [Condition], createdAt: Date) {
        self.name = name
        self.createdAt = createdAt
        self.conditions = conditions
    }

    var status: Status {
        get { Status(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var conditions: [Condition] {
        get { (try? JSONDecoder().decode([Condition].self, from: conditionsData)) ?? [] }
        set { conditionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

/// The app's record of a Sorted Playlist it created in Apple Music. The playlist is
/// referred to only by its ID, so renaming it in Music doesn't matter.
@Model
final class SortedPlaylistRecord {
    var rule: Rule?
    var playlistID: String = ""
    var createdAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \Placement.sortedPlaylist)
    var placements: [Placement]? = []

    init(rule: Rule, playlistID: String, createdAt: Date) {
        self.rule = rule
        self.playlistID = playlistID
        self.createdAt = createdAt
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

/// App-wide state; there is at most one instance.
@Model
final class AppState {
    var lastSortingRunAt: Date?

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
        AppState.self,
    ]
}
