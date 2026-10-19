//
//  RuleListView.swift
//  MusicSorter
//

import OSLog
import SwiftData
import SwiftUI

/// The Rules, their Sorted Playlists' Song counts, "Last sorted" and "Sort now". A Rule is
/// edited by tapping it, and started over or deleted from its swipe actions or context menu.
struct RuleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.createdAt) private var rules: [Rule]
    @Query private var appStates: [AppState]

    @State private var gateway = MusicKitLibraryGateway()
    @State private var isSorting = false
    @State private var isAddingRule = false
    @State private var sortError: String?
    @State private var editedRule: Rule?
    @State private var ruleStartingOver: Rule?
    @State private var ruleBeingDeleted: Rule?

    var body: some View {
        NavigationStack {
            List {
                if appStates.first?.isShazamPlaylistMissing == true {
                    Section {
                        ShazamSyncBanner()
                    }
                }
                Section {
                    ForEach(rules) { rule in
                        Button {
                            editedRule = rule
                        } label: {
                            RuleRow(rule: rule)
                        }
                        .tint(.primary)
                        // A Sorting Run in progress holds on to the Rules it fetched, so they
                        // aren't changed until it ends.
                        .disabled(isSorting)
                        .swipeActions {
                            // Not `.destructive`: that removes the row before the user confirms.
                            Button("Delete", systemImage: "trash") {
                                ruleBeingDeleted = rule
                            }
                            .tint(.red)
                            if rule.canStartOver {
                                Button("Start Over", systemImage: "arrow.counterclockwise") {
                                    ruleStartingOver = rule
                                }
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                editedRule = rule
                            }
                            if rule.canStartOver {
                                Button("Start Over in a New Playlist", systemImage: "arrow.counterclockwise") {
                                    ruleStartingOver = rule
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ruleBeingDeleted = rule
                            }
                        }
                    }
                } footer: {
                    lastSortedText
                }
            }
            .overlay {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "No Rules",
                        systemImage: "line.3.horizontal.decrease",
                        description: Text("Add a Rule to start sorting your Favorite Songs and Shazams.")
                    )
                }
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Rule", systemImage: "plus") {
                        isAddingRule = true
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await sortNow() }
                    } label: {
                        if isSorting {
                            ProgressView()
                        } else {
                            Text("Sort Now")
                        }
                    }
                    .disabled(isSorting || rules.isEmpty)
                }
            }
            .sheet(isPresented: $isAddingRule) {
                RuleEditorView()
            }
            .sheet(item: $editedRule) { rule in
                RuleEditorView(rule: rule)
            }
            .confirmationDialog(
                "Start over in a new playlist?",
                isPresented: Binding(
                    get: { ruleStartingOver != nil },
                    set: { if !$0 { ruleStartingOver = nil } }
                ),
                titleVisibility: .visible,
                presenting: ruleStartingOver
            ) { rule in
                Button("Start Over") { rule.startOver() }
                Button("Cancel", role: .cancel) {}
            } message: { rule in
                Text(Self.startOverMessage(for: rule))
            }
            .confirmationDialog(
                "Delete this Rule?",
                isPresented: Binding(
                    get: { ruleBeingDeleted != nil },
                    set: { if !$0 { ruleBeingDeleted = nil } }
                ),
                titleVisibility: .visible,
                presenting: ruleBeingDeleted
            ) { rule in
                Button("Delete Rule", role: .destructive) { modelContext.delete(rule) }
                Button("Cancel", role: .cancel) {}
            } message: { rule in
                Text(Self.deleteMessage(for: rule))
            }
            .alert("Sorting Failed", isPresented: .constant(sortError != nil)) {
                Button("OK") { sortError = nil }
            } message: {
                Text(sortError ?? "")
            }
        }
    }

    private static let logger = Logger(subsystem: "it.angedell.MusicSorter", category: "SortingRun")

    private var lastSortedText: Text {
        if let date = appStates.first?.lastSortingRunAt {
            Text("Last sorted: \(date, format: .relative(presentation: .named))")
        } else {
            Text("Last sorted: never")
        }
    }

    /// MusicKit can't delete playlists, so the old ones are left for the user (ADR 0001).
    private static func startOverMessage(for rule: Rule) -> String {
        if rule.isGrouped {
            return "On the next sort, each group gets a new Sorted Playlist with every Song that meets \"\(rule.name)\" then. The current group playlists stay in Music but won't get new Songs; you can delete them in the Music app."
        }
        let name = rule.currentSortedPlaylist?.name ?? rule.sortedPlaylistName
        return "On the next sort, a new Sorted Playlist is created with every Song that meets \"\(rule.name)\" then. \"\(name)\" stays in Music but won't get new Songs; you can delete it in the Music app."
    }

    private static func deleteMessage(for rule: Rule) -> String {
        let playlistCount = rule.sortedPlaylists?.count ?? 0
        return switch playlistCount {
        case 0: "MusicSorter will stop applying \"\(rule.name)\"."
        case 1: "MusicSorter will stop applying \"\(rule.name)\". It can't delete playlists from Music, so its Sorted Playlist stays there; you can delete it in the Music app."
        default: "MusicSorter will stop applying \"\(rule.name)\". It can't delete playlists from Music, so its \(playlistCount) Sorted Playlists stay there; you can delete them in the Music app."
        }
    }

    private func sortNow() async {
        isSorting = true
        defer { isSorting = false }
        let start = ContinuousClock.now
        do {
            let summary = try await SortingEngine(gateway: gateway, modelContext: modelContext).run(now: .now)
            Self.logger.info("Sorting Run placed \(summary.placementCount) songs, created \(summary.createdPlaylistCount) playlists, with \(summary.warnings.count) warnings, in \(ContinuousClock.now - start)")
        } catch {
            sortError = error.localizedDescription
        }
    }
}

private struct RuleRow: View {
    let rule: Rule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.name)
                .font(.headline)
            ForEach(rule.conditions, id: \.self) { condition in
                Text(condition.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if rule.isGrouped {
                if let grouping = rule.grouping {
                    Text(grouping.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                let groupPlaylists = rule.groupPlaylists
                ForEach(groupPlaylists) { playlist in
                    Text("\(playlist.name): \(playlist.songCount) songs")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if groupPlaylists.isEmpty {
                    Text("A group's Sorted Playlist is created once it has \(rule.groupThreshold) songs")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(playlistSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playlistSummary: String {
        guard let playlist = rule.currentSortedPlaylist else {
            return "Sorted Playlist created on the next sort"
        }
        return "\(playlist.name): \(playlist.songCount) songs"
    }
}

/// Shown while the last Sorting Run found no "My Shazam Tracks" playlist (ADR 0002).
private struct ShazamSyncBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shazams aren't being sorted")
                    .font(.headline)
                Text("MusicSorter couldn't find \"My Shazam Tracks\", so only Favorite Songs were sorted. In the Shazam app, open Settings and turn on Sync to Apple Music. Your Shazams will be sorted on the next run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "shazam.logo")
        }
    }
}

#Preview {
    RuleListView()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
