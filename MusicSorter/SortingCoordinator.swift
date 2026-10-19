//
//  SortingCoordinator.swift
//  MusicSorter
//

import Foundation
import Observation
import OSLog
import SwiftData

/// Starts every Sorting Run, whether the app came to the foreground, iOS granted
/// background refresh time or the user tapped "Sort Now", so that only one runs at a time.
@Observable
final class SortingCoordinator {
    /// Whether a Sorting Run is in progress. Rules aren't changed while one is, since the
    /// run holds on to the Rules it fetched.
    private(set) var isSorting = false

    @ObservationIgnored private let gateway: any MusicLibraryGateway
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var currentRun: Task<SortingRunSummary, any Error>?
    /// Counts the runs started, so a run that ends after a newer one started leaves the
    /// newer one's state alone.
    @ObservationIgnored private var startedRunCount = 0

    init(gateway: any MusicLibraryGateway, modelContext: ModelContext, now: @escaping () -> Date = { .now }) {
        self.gateway = gateway
        self.modelContext = modelContext
        self.now = now
    }

    /// Runs a Sorting Run, or waits for the one in progress, and returns what it did.
    /// Cancelling the caller's task, e.g. when background time expires, stops the run
    /// before its next change to Apple Music, for every caller waiting on it.
    @discardableResult
    func sort() async throws -> SortingRunSummary {
        let run = if let currentRun, !currentRun.isCancelled { currentRun } else { startRun(after: currentRun) }
        return try await withTaskCancellationHandler {
            try await run.value
        } onCancel: {
            run.cancel()
        }
    }

    /// Runs a Sorting Run the user didn't ask for, logging rather than reporting a failure;
    /// the next run picks up where this one stopped.
    func sortAutomatically(reason: String) async {
        do {
            try await sort()
        } catch is CancellationError {
            Logger.sortingRun.info("Sorting Run (\(reason, privacy: .public)) stopped before completing")
        } catch {
            Logger.sortingRun.error("Sorting Run (\(reason, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Starts a Sorting Run once `previous`, a cancelled run that hasn't stopped yet, ends.
    private func startRun(after previous: Task<SortingRunSummary, any Error>?) -> Task<SortingRunSummary, any Error> {
        isSorting = true
        startedRunCount += 1
        let runNumber = startedRunCount
        let engine = SortingEngine(gateway: gateway, modelContext: modelContext)
        let run = Task {
            defer {
                if startedRunCount == runNumber {
                    currentRun = nil
                    isSorting = false
                }
            }
            _ = await previous?.result
            let start = ContinuousClock.now
            let summary = try await engine.run(now: now())
            Logger.sortingRun.info("Sorting Run placed \(summary.placementCount) songs, created \(summary.createdPlaylistCount) playlists, with \(summary.warnings.count) warnings, in \(ContinuousClock.now - start)")
            return summary
        }
        currentRun = run
        return run
    }
}

extension Logger {
    nonisolated static let sortingRun = Logger(subsystem: "it.angedell.MusicSorter", category: "SortingRun")
}
