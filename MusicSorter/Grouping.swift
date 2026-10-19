//
//  Grouping.swift
//  MusicSorter
//

import Foundation

/// What a Grouped Rule groups its Songs by. Each Group's value names its Sorted Playlist.
enum Grouping: Hashable {
    /// The first genre other than the catch-all "Music", so each Song is in one Group.
    case primaryGenre
    /// The Song's first linked artist.
    case artist
    case releaseDecade
    /// The year of the Song's First Seen in `source` or, with no source, its earliest First
    /// Seen. As with a First Seen Condition, the year is read in the time zone the Rule was
    /// made in, so a Song can't move to another Group when the user travels (ADR 0001).
    case firstSeenYear(in: SourcePlaylist?, timeZone: TimeZone)

    /// Groups by First Seen year read in the device's current time zone.
    static func firstSeenYear(in source: SourcePlaylist?) -> Self {
        .firstSeenYear(in: source, timeZone: .current)
    }

    /// The Song's Group, or `nil` if the Song lacks the value and is left out.
    func value(for song: LibrarySong) -> String? {
        switch self {
        case .primaryGenre:
            song.primaryGenre
        case .artist:
            song.firstArtistName
        case .releaseDecade:
            song.releaseDecade.map { "\(String($0))s" }
        case .firstSeenYear(let source, let timeZone):
            song.firstSeen(in: source).map { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                return String(calendar.component(.year, from: date))
            }
        }
    }

    /// How the Grouping reads in the UI.
    var summary: String {
        switch self {
        case .primaryGenre: "Grouped by genre"
        case .artist: "Grouped by artist"
        case .releaseDecade: "Grouped by release decade"
        case .firstSeenYear(let source, _):
            if let source {
                "Grouped by year first seen in \(source.displayName)"
            } else {
                "Grouped by year first seen"
            }
        }
    }
}

/// Nonisolated so a Rule can store its Grouping from SwiftData's nonisolated contexts.
nonisolated extension Grouping: Codable {}
