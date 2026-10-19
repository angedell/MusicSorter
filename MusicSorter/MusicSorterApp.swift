//
//  MusicSorterApp.swift
//  MusicSorter
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import BackgroundTasks
import OSLog
import SwiftUI
import SwiftData

@main
struct MusicSorterApp: App {
    /// The background app refresh task that runs a Sorting Run. Listed under
    /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    nonisolated static let sortingRunTaskIdentifier = "it.angedell.MusicSorter.sortingRun"
    /// How long after a run iOS is asked, at the earliest, for time for the next one.
    private nonisolated static let backgroundRunInterval: TimeInterval = 30 * 60

    @Environment(\.scenePhase) private var scenePhase

    let sharedModelContainer: ModelContainer
    @State private var coordinator: SortingCoordinator

    init() {
        let schema = Schema(MusicSorterSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        _coordinator = State(initialValue: SortingCoordinator(
            gateway: MusicKitLibraryGateway(),
            modelContext: sharedModelContainer.mainContext
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .environment(coordinator)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Task { await coordinator.sortAutomatically(reason: "foreground") }
            case .background:
                Task { await Self.scheduleBackgroundRun() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Self.sortingRunTaskIdentifier)) { [coordinator] in
            // Rescheduled first, so a run that's cut short still leads to the next one.
            await Self.scheduleBackgroundRun()
            // SwiftUI cancels this task when background time expires, which stops the run
            // before its next change to Apple Music. A blocked run places nothing, so posts
            // nothing.
            if let summary = await coordinator.sortAutomatically(reason: "background refresh") {
                await SummaryNotification.postIfEnabled(for: summary)
            }
        }
    }

    /// Asks iOS for background time for the next Sorting Run, replacing any earlier request.
    /// Off the main actor, as `BGTaskScheduler` asks.
    @concurrent
    private nonisolated static func scheduleBackgroundRun() async {
        let request = BGAppRefreshTaskRequest(identifier: sortingRunTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundRunInterval)
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error {
                Logger.sortingRun.error("Couldn't schedule a background Sorting Run: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
