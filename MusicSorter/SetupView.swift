//
//  SetupView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// First-run setup once Music access is granted: checks for "My Shazam Tracks", then
/// suggests starter Rules. Nothing is created unless the user accepts a suggestion.
struct SetupView: View {
    /// The `UserDefaults` key recording that setup was finished or skipped.
    static let isCompletedKey = "hasCompletedSetup"

    let finish: () -> Void

    private enum Step {
        case shazamCheck
        case starterRules
    }

    @State private var step = Step.shazamCheck

    var body: some View {
        NavigationStack {
            switch step {
            case .shazamCheck:
                ShazamCheckStep { step = .starterRules }
            case .starterRules:
                StarterRulesStep(finish: finish)
            }
        }
    }
}

/// Looks for "My Shazam Tracks", without changing anything, and explains Shazam's "Sync to
/// Apple Music" if it's missing.
private struct ShazamCheckStep: View {
    let next: () -> Void

    private enum CheckState {
        case checking
        case found
        case missing
        case failed
    }

    @Environment(SortingCoordinator.self) private var coordinator
    @State private var checkState = CheckState.checking

    var body: some View {
        Group {
            switch checkState {
            case .checking:
                ProgressView("Looking for your Shazams…")
            case .found:
                ContentUnavailableView {
                    Label("Shazams Found", systemImage: "shazam.logo")
                } description: {
                    Text("MusicSorter will sort the songs in \"My Shazam Tracks\" along with your Favorite Songs.")
                } actions: {
                    Button("Continue", action: next)
                        .buttonStyle(.borderedProminent)
                }
            case .missing:
                ContentUnavailableView {
                    Label("Turn On Shazam Sync", systemImage: "shazam.logo")
                } description: {
                    Text("MusicSorter couldn't find \"My Shazam Tracks\". In the Shazam app, open Settings and turn on Sync to Apple Music. Until then, only Favorite Songs are sorted.")
                } actions: {
                    Button("Check Again") {
                        Task { await check() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Continue Without Shazams", action: next)
                }
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't Check for Shazams", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("MusicSorter couldn't read your Apple Music library. You can try again, or continue and it will look again on the next sort.")
                } actions: {
                    Button("Try Again") {
                        Task { await check() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Continue", action: next)
                }
            }
        }
        .navigationTitle("Set Up")
        .task { await check() }
    }

    private func check() async {
        checkState = .checking
        do {
            checkState = try await coordinator.sourcePlaylistExists(.myShazamTracks) ? .found : .missing
        } catch {
            checkState = .failed
        }
    }
}

/// Suggests starter Rules, each created with one tap.
private struct StarterRulesStep: View {
    let finish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SortingCoordinator.self) private var coordinator
    @Query private var rules: [Rule]

    var body: some View {
        List {
            Section {
                ForEach(StarterRule.allCases) { starter in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(starter.title)
                                    .font(.headline)
                                Text(starter.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: starter.systemImage)
                        }
                        Spacer()
                        if starter.isAdded(among: rules) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Added")
                        } else {
                            Button("Add") {
                                starter.add(to: modelContext, now: .now)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Add \(starter.title)")
                        }
                    }
                }
            } footer: {
                Text("Sorted Playlists are created in your Apple Music library on the next sort. You can add, edit or delete Rules at any time.")
            }
        }
        .navigationTitle("Starter Rules")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(rules.isEmpty ? "Skip" : "Done") {
                    finish()
                    // Creates the accepted Rules' Sorted Playlists now rather than on the
                    // next opening.
                    if !rules.isEmpty {
                        Task { await coordinator.sortAutomatically(reason: "setup finished") }
                    }
                }
            }
        }
    }
}
