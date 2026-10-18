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
            Self.releaseYear(of: song) == year
        case .releasedInDecade(let decade):
            Self.releaseYear(of: song).map { $0 / 10 * 10 == decade } ?? false
        }
    }

    /// Apple Music release dates are calendar days stored as midnight UTC, so the year is
    /// read in UTC; in the device's time zone 1 January could fall in the year before.
    private static func releaseYear(of song: LibrarySong) -> Int? {
        guard let releaseDate = song.releaseDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: releaseDate)
    }

    /// Names typed by the user match Apple Music's regardless of case and accents.
    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// The genre Apple Music lists for nearly every Song, which says nothing about it.
    private static let catchAllGenre = "Music"

    /// How the Condition reads in the UI.
    var summary: String {
        switch self {
        case .playCountAtLeast(let count): "Played at least \(count) times"
        case .sourcePlaylistIs(let source): "In \(source.displayName)"
        case .genreIs(let genre): "Genre is \(genre)"
        case .artistIs(let artist): "By \(artist)"
        case .releasedInYear(let year): "Released in \(String(year))"
        case .releasedInDecade(let decade): "Released in the \(String(decade))s"
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
