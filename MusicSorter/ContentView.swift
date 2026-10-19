//
//  ContentView.swift
//  MusicSorter
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import MusicKit
import SwiftData
import SwiftUI

/// Gates the app on Apple Music access and a subscription, then shows first-run setup once
/// and the Rules after it. Access is checked again whenever the app comes to the
/// foreground, so a blocking screen clears once the problem is fixed.
struct ContentView: View {
    private enum Access {
        /// Music access hasn't been asked for yet.
        case notRequested
        case blocked(SortingBlocker)
        case granted
    }

    /// `nil` until first checked.
    @State private var access: Access?
    @AppStorage(SetupView.isCompletedKey) private var hasCompletedSetup = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(SortingCoordinator.self) private var coordinator

    var body: some View {
        Group {
            switch access {
            case nil:
                ProgressView()
            case .notRequested:
                MusicAccessRequestView {
                    _ = await MusicAuthorization.request()
                    await refreshAccess()
                }
            case .blocked(.noMusicAccess):
                MusicAccessDeniedView()
            case .blocked(.noSubscription):
                SubscriptionRequiredView {
                    await refreshAccess()
                }
            case .granted:
                if hasCompletedSetup {
                    RuleListView()
                } else {
                    SetupView { hasCompletedSetup = true }
                }
            }
        }
        .onAppear {
            // Someone who made Rules before first-run setup existed doesn't need it.
            if !hasCompletedSetup, ((try? modelContext.fetchCount(FetchDescriptor<Rule>())) ?? 0) > 0 {
                hasCompletedSetup = true
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await refreshAccess() }
            }
        }
    }

    private func refreshAccess() async {
        // On opening the app, `access` is still unchecked and the app's own run covers it.
        let wasBlocked = switch access {
        case .notRequested, .blocked: true
        case .granted, nil: false
        }
        if MusicAuthorization.currentStatus == .notDetermined {
            access = .notRequested
        } else if let blocker = await coordinator.sortingBlocker() {
            access = .blocked(blocker)
        } else {
            access = .granted
            // The run on coming to the foreground may have been blocked before the problem
            // was fixed.
            if wasBlocked {
                await coordinator.sortAutomatically(reason: "access granted")
            }
        }
    }
}

/// The first setup step: asks for access to the Apple Music library.
private struct MusicAccessRequestView: View {
    let requestAccess: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Apple Music Access", systemImage: "music.note.list")
        } description: {
            Text("MusicSorter reads your Favorite Songs and Shazams and files them into Sorted Playlists in your library.")
        } actions: {
            Button("Allow Access") {
                Task { await requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Blocks the app while Music access is denied or restricted.
private struct MusicAccessDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("No Access to Apple Music", systemImage: "lock")
        } description: {
            Text("MusicSorter needs access to your Apple Music library to read your Favorite Songs and Shazams and to create Sorted Playlists. Turn on access to Media & Apple Music in Settings.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Blocks the app while the user has no Apple Music subscription.
private struct SubscriptionRequiredView: View {
    /// Called when the subscription offer closes, in case the user subscribed.
    let offerDidClose: () async -> Void
    @State private var isShowingOffer = false

    var body: some View {
        ContentUnavailableView {
            Label("Apple Music Subscription Required", systemImage: "music.note")
        } description: {
            Text("MusicSorter files your songs into Sorted Playlists in your Apple Music library, which needs an Apple Music subscription.")
        } actions: {
            Button("Subscribe to Apple Music") {
                isShowingOffer = true
            }
            .buttonStyle(.borderedProminent)
        }
        .musicSubscriptionOffer(isPresented: $isShowingOffer)
        .onChange(of: isShowingOffer) { _, isShowing in
            if !isShowing {
                Task { await offerDidClose() }
            }
        }
    }
}
