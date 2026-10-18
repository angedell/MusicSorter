//
//  Condition.swift
//  MusicSorter
//

import Foundation

/// One test within a Rule. Only Conditions a Song can't stop meeting are allowed (ADR 0001).
///
/// Everything a new kind of Condition needs (how it's checked and how it's described)
/// lives in this file.
enum Condition: Codable, Hashable {
    case playCountAtLeast(Int)
    case sourcePlaylistIs(SourcePlaylist)

    func isMet(by song: LibrarySong) -> Bool {
        switch self {
        case .playCountAtLeast(let minimum):
            // Songs not in the library have no play count and count as 0 plays.
            (song.playCount ?? 0) >= minimum
        case .sourcePlaylistIs(let source):
            song.sources.contains(source)
        }
    }

    /// How the Condition reads in the UI.
    var summary: String {
        switch self {
        case .playCountAtLeast(let count): "Played at least \(count) times"
        case .sourcePlaylistIs(let source): "In \(source.displayName)"
        }
    }
}

extension Rule {
    /// Whether the Song meets every one of the Rule's Conditions. If the stored Conditions
    /// can't be read, they can't be checked, so they count as not met.
    func isMet(by song: LibrarySong) -> Bool {
        guard let conditions = storedConditions else { return false }
        return conditions.allSatisfy { $0.isMet(by: song) }
    }
}
