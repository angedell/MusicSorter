//
//  SummaryNotification.swift
//  MusicSorter
//

import Foundation
import OSLog
import UserNotifications

/// The optional local notification posted after a background Sorting Run that placed Songs,
/// e.g. "Placed 6 songs into 3 playlists."
enum SummaryNotification {
    /// The `UserDefaults` key of the setting, off by default.
    static let isEnabledKey = "postsSummaryNotification"

    /// The notification's message, or nil for a run that placed nothing.
    static func message(for summary: SortingRunSummary) -> String? {
        guard summary.placementCount > 0 else { return nil }
        let songs = summary.placementCount == 1 ? "1 song" : "\(summary.placementCount) songs"
        let playlists = summary.placedIntoPlaylistCount == 1 ? "1 playlist" : "\(summary.placedIntoPlaylistCount) playlists"
        return "Placed \(songs) into \(playlists)."
    }

    /// Asks for permission to post notifications, returning whether it was granted.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            Logger.sortingRun.error("Couldn't ask for notification permission: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Posts the summary of a background Sorting Run if the setting is on and the run
    /// placed something.
    static func postIfEnabled(for summary: SortingRunSummary) async {
        guard UserDefaults.standard.bool(forKey: isEnabledKey), let message = message(for: summary) else { return }
        let content = UNMutableNotificationContent()
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.sortingRun.error("Couldn't post the Sorting Run summary: \(error.localizedDescription, privacy: .public)")
        }
    }
}
