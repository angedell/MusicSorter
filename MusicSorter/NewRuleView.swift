//
//  NewRuleView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// Creates a Rule with a "played at least N times" Condition and, optionally, a
/// "Source Playlist is …" Condition.
struct NewRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var minimumPlayCount = 10
    /// `nil` means Songs from any Source Playlist.
    @State private var source: SourcePlaylist?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conditions: [Condition] {
        var conditions: [Condition] = [.playCountAtLeast(minimumPlayCount)]
        if let source {
            conditions.append(.sourcePlaylistIs(source))
        }
        return conditions
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text("The Sorted Playlist will be called \"\(Rule.sortedPlaylistName(forRuleNamed: trimmedName.isEmpty ? "Name" : trimmedName))\".")
                }
                Section("Conditions") {
                    Stepper(
                        "Played at least \(minimumPlayCount) times",
                        value: $minimumPlayCount,
                        in: 1...9_999
                    )
                    Picker("Source Playlist", selection: $source) {
                        Text("Any").tag(SourcePlaylist?.none)
                        ForEach(SourcePlaylist.allCases, id: \.self) { source in
                            Text(source.displayName).tag(SourcePlaylist?.some(source))
                        }
                    }
                }
            }
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        modelContext.insert(Rule(
                            name: trimmedName,
                            conditions: conditions,
                            createdAt: .now
                        ))
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NewRuleView()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
