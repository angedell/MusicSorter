//
//  MusicSorterApp.swift
//  MusicSorter
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import SwiftUI
import SwiftData

@main
struct MusicSorterApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(MusicSorterSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
