//
//  ContentView.swift
//  MusicSorter
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import MusicKit
import SwiftUI

/// Gates the app on Apple Music access.
struct ContentView: View {
    @State private var authorization = MusicAuthorization.currentStatus
    @Environment(\.openURL) private var openURL
    @Environment(SortingCoordinator.self) private var coordinator

    var body: some View {
        switch authorization {
        case .authorized:
            RuleListView()
        case .notDetermined:
            ContentUnavailableView {
                Label("Apple Music Access", systemImage: "music.note.list")
            } description: {
                Text("MusicSorter reads your Favorite Songs and Shazams and files them into Sorted Playlists in your library.")
            } actions: {
                Button("Allow Access") {
                    Task {
                        authorization = await MusicAuthorization.request()
                        // The app is already in the foreground, so the run on opening it
                        // was skipped for lack of access.
                        if authorization == .authorized {
                            await coordinator.sortAutomatically(reason: "access granted")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            ContentUnavailableView {
                Label("No Access to Apple Music", systemImage: "lock")
            } description: {
                Text("MusicSorter can't sort without access to your Apple Music library. Turn it on in Settings.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
    }
}
