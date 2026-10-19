//
//  StarterRule.swift
//  MusicSorter
//

import Foundation
import SwiftData

/// A Rule first-run setup suggests. It's created only when the user accepts it.
enum StarterRule: CaseIterable, Identifiable {
    case groupByPrimaryGenre
    case playedTwentyTimes

    var id: Self { self }

    /// The name of the Rule created.
    var ruleName: String {
        switch self {
        case .groupByPrimaryGenre: "By Genre"
        case .playedTwentyTimes: "Played 20+ Times"
        }
    }

    /// How the suggestion reads in setup.
    var title: String {
        switch self {
        case .groupByPrimaryGenre: "Group by Primary Genre"
        case .playedTwentyTimes: "Played 20+ times"
        }
    }

    var explanation: String {
        switch self {
        case .groupByPrimaryGenre: "A Sorted Playlist per genre, such as \"Jazz · Sorted\", once the genre has 5 songs."
        case .playedTwentyTimes: "\"Played 20+ Times · Sorted\", holding every song you've played at least 20 times."
        }
    }

    var systemImage: String {
        switch self {
        case .groupByPrimaryGenre: "guitars"
        case .playedTwentyTimes: "repeat"
        }
    }

    /// Creates the suggested Rule.
    func add(to context: ModelContext, now: Date) {
        let rule = switch self {
        case .groupByPrimaryGenre:
            Rule(name: ruleName, conditions: [], grouping: .primaryGenre, groupThreshold: 5, createdAt: now)
        case .playedTwentyTimes:
            Rule(name: ruleName, conditions: [.playCountAtLeast(20)], createdAt: now)
        }
        context.insert(rule)
    }

    /// Whether the suggestion was already accepted, e.g. before setup was interrupted, so
    /// it isn't created twice.
    func isAdded(among rules: [Rule]) -> Bool {
        rules.contains { $0.name == ruleName }
    }
}
