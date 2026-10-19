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
    /// Met when any of the Song's genres, other than the catch-all "Music", has this name.
    case genreIs(String)
    /// Met when the Song's credited artist has this name.
    case artistIs(String)
    /// Met when the Song was released in this year.
    case releasedInYear(Int)
    /// The decade is given by its first year, e.g. 1990 for 1990–1999.
    case releasedInDecade(Int)
    /// Met when the Song's First Seen in `source` falls in the period. With no source, the
    /// Song's earliest First Seen in any Source Playlist is used. Either way the date never
    /// changes once recorded, so a Song can't stop meeting this Condition.
    case firstSeen(FirstSeenPeriod, in: SourcePlaylist?)

    func isMet(by song: LibrarySong) -> Bool {
        switch self {
        case .playCountAtLeast(let minimum):
            // Songs not in the library have no play count and count as 0 plays.
            (song.playCount ?? 0) >= minimum
        case .sourcePlaylistIs(let source):
            song.sources.contains(source)
        case .genreIs(let genre):
            song.genres.contains { Self.sameName($0, genre) && !Self.sameName($0, Self.catchAllGenre) }
        case .artistIs(let artist):
            song.artistName.map { Self.sameName($0, artist) } ?? false
        case .releasedInYear(let year):
            song.releaseYear == year
        case .releasedInDecade(let decade):
            song.releaseDecade == decade
        case .firstSeen(let period, let source):
            song.firstSeen(in: source).map(period.contains) ?? false
        }
    }

    /// Names typed by the user match Apple Music's regardless of case and accents.
    static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// The genre Apple Music lists for nearly every Song, which says nothing about it.
    static let catchAllGenre = "Music"

    /// How the Condition reads in the UI.
    var summary: String {
        switch self {
        case .playCountAtLeast(let count): "Played at least \(count) times"
        case .sourcePlaylistIs(let source): "In \(source.displayName)"
        case .genreIs(let genre): "Genre is \(genre)"
        case .artistIs(let artist): "By \(artist)"
        case .releasedInYear(let year): "Released in \(String(year))"
        case .releasedInDecade(let decade): "Released in the \(String(decade))s"
        case .firstSeen(let period, let source):
            if let source {
                "First seen in \(source.displayName) \(period.summary)"
            } else {
                "First seen \(period.summary)"
            }
        }
    }
}

/// When a First Seen Condition's Songs were first seen. First Seen is a moment in the
/// user's own life, so years and days are read in the time zone the user was in when they
/// made the Rule. That time zone is kept with the period: reading it in whatever time zone
/// the device is in now would let a Song first seen near midnight stop meeting the
/// Condition after the user travels (ADR 0001).
struct FirstSeenPeriod: Codable, Hashable {
    enum Span: Codable, Hashable {
        case year(Int)
        /// Both days are included, whatever their time of day.
        case between(firstDay: Date, lastDay: Date)
    }

    var span: Span
    var timeZone: TimeZone

    static func year(_ year: Int, in timeZone: TimeZone = .current) -> Self {
        Self(span: .year(year), timeZone: timeZone)
    }

    static func between(firstDay: Date, lastDay: Date, in timeZone: TimeZone = .current) -> Self {
        Self(span: .between(firstDay: firstDay, lastDay: lastDay), timeZone: timeZone)
    }

    func contains(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch span {
        case .year(let year):
            return calendar.component(.year, from: date) == year
        case .between(let firstDay, let lastDay):
            guard let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else {
                return false
            }
            return calendar.startOfDay(for: firstDay) <= date && date < dayAfterLast
        }
    }

    var summary: String {
        switch span {
        case .year(let year):
            return "in \(String(year))"
        case .between(let firstDay, let lastDay):
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone)
            return "between \(firstDay.formatted(style)) and \(lastDay.formatted(style))"
        }
    }
}

/// Song attributes read the same way by Conditions and Groupings.
extension LibrarySong {
    /// Apple Music release dates are calendar days stored as midnight UTC, so the year is
    /// read in UTC; in the device's time zone 1 January could fall in the year before.
    var releaseYear: Int? {
        guard let releaseDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: releaseDate)
    }

    /// The decade's first year, e.g. 1990 for 1990–1999.
    var releaseDecade: Int? {
        releaseYear.map { $0 / 10 * 10 }
    }

    /// The first genre listed other than the catch-all "Music".
    var primaryGenre: String? {
        genres.first { !Condition.sameName($0, Condition.catchAllGenre) }
    }

    /// The Song's First Seen in `source` or, with no source, its earliest First Seen in
    /// any Source Playlist.
    func firstSeen(in source: SourcePlaylist?) -> Date? {
        if let source {
            firstSeen[source]
        } else {
            firstSeen.values.min()
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
