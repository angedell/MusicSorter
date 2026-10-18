//
//  NewRuleView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// Creates a Rule with a single "played at least N times" Condition.
struct NewRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var minimumPlayCount = 10

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text("The Sorted Playlist will be called \"\(Rule.sortedPlaylistName(forRuleNamed: trimmedName.isEmpty ? "Name" : trimmedName))\".")
                }
                Section("Condition") {
                    Stepper(
                        "Played at least \(minimumPlayCount) times",
                        value: $minimumPlayCount,
                        in: 1...9_999
                    )
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
                            conditions: [.playCountAtLeast(minimumPlayCount)],
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
