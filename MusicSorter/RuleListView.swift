//
//  RuleListView.swift
//  MusicSorter
//

import OSLog
import SwiftData
import SwiftUI

/// The Rules, their Sorted Playlists' Song counts, "Last sorted" and "Sort now".
struct RuleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.createdAt) private var rules: [Rule]
    @Query private var appStates: [AppState]

    @State private var gateway = MusicKitLibraryGateway()
    @State private var isSorting = false
    @State private var isAddingRule = false
    @State private var sortError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rules) { rule in
                        RuleRow(rule: rule)
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
                        description: Text("Add a Rule to start sorting your Favorite Songs.")
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
                NewRuleView()
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

    private func sortNow() async {
        isSorting = true
        defer { isSorting = false }
        let start = ContinuousClock.now
        do {
            let summary = try await SortingEngine(gateway: gateway, modelContext: modelContext).run(now: .now)
            Self.logger.info("Sorting Run placed \(summary.placementCount) songs, created \(summary.createdPlaylistCount) playlists, in \(ContinuousClock.now - start)")
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
            Text(playlistSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var playlistSummary: String {
        guard let playlist = rule.currentSortedPlaylist else {
            return "Sorted Playlist created on the next sort"
        }
        return "\(rule.sortedPlaylistName): \(playlist.songCount) songs"
    }
}

#Preview {
    RuleListView()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
