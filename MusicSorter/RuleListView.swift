//
//  RuleListView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// The Rules, their Sorted Playlists' Song counts, "Last sorted" and "Sort now". A Rule is
/// edited by tapping it, and started over or deleted from its swipe actions or context menu.
struct RuleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.createdAt) private var rules: [Rule]
    @Query private var appStates: [AppState]

    @Environment(SortingCoordinator.self) private var coordinator
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
                ForEach(rules.filter { $0.status == .paused }) { rule in
                    Section {
                        PausedRuleBanner(rule: rule)
                        Button("Resume \"\(rule.name)\"", systemImage: "play") {
                            rule.resume()
                        }
                        .disabled(isSorting)
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

    /// Whether a Sorting Run is in progress, including one started automatically.
    private var isSorting: Bool { coordinator.isSorting }

    private func sortNow() async {
        do {
            try await coordinator.sort()
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
            if rule.status == .paused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
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
                    Text(Self.summary(of: playlist))
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
        return Self.summary(of: playlist)
    }

    private static func summary(of playlist: SortedPlaylistRecord) -> String {
        playlist.isDeletedInMusic
            ? "\(playlist.name): deleted in Music"
            : "\(playlist.name): \(playlist.songCount) songs"
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

/// Explains why a Rule is a Paused Rule and what resuming it does.
private struct PausedRuleBanner: View {
    let rule: Rule

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("\"\(rule.name)\" is paused")
                    .font(.headline)
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
        }
    }

    private var explanation: String {
        let names = rule.deletedSortedPlaylists.map { "\"\($0.name)\"" }
        let deleted = names.isEmpty
            ? "One of its Sorted Playlists was"
            : names.formatted(.list(type: .and)) + (names.count == 1 ? " was" : " were")
        let recreated = names.count > 1 ? "new playlists" : "a new playlist"
        return "\(deleted) deleted in the Music app, so MusicSorter stopped applying this Rule. Resume to create \(recreated) on the next sort with every Song that meets the Rule."
    }
}

/// Gives the previewed list a coordinator over the preview's store.
private struct RuleListPreview: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RuleListView()
            .environment(SortingCoordinator(gateway: MusicKitLibraryGateway(), modelContext: modelContext))
    }
}

#Preview {
    RuleListPreview()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
