//
//  NewRuleView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// Creates a Rule from any combination of Conditions: play count, Source Playlist, genre,
/// artist, release decade or year and First Seen.
struct NewRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Which release Condition, if any, the Rule has.
    private enum ReleaseOption: Hashable {
        case any
        case decade
        case year
    }

    /// Which First Seen Condition, if any, the Rule has.
    private enum FirstSeenOption: Hashable {
        case any
        case year
        case between
    }

    @State private var name = ""
    @State private var requiresPlayCount = true
    @State private var minimumPlayCount = 10
    /// `nil` means Songs from any Source Playlist.
    @State private var source: SourcePlaylist?
    @State private var genre = ""
    @State private var artist = ""
    @State private var releaseOption = ReleaseOption.any
    @State private var releaseDecade = 1990
    @State private var releaseYear = Calendar.current.component(.year, from: .now)
    @State private var firstSeenOption = FirstSeenOption.any
    @State private var firstSeenYear = Calendar.current.component(.year, from: .now)
    @State private var firstSeenFirstDay = Date.now
    @State private var firstSeenLastDay = Date.now

    private static let latestYear = Calendar.current.component(.year, from: .now) + 1

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conditions: [Condition] {
        var conditions: [Condition] = []
        if requiresPlayCount {
            conditions.append(.playCountAtLeast(minimumPlayCount))
        }
        if let source {
            conditions.append(.sourcePlaylistIs(source))
        }
        let genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !genre.isEmpty {
            conditions.append(.genreIs(genre))
        }
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty {
            conditions.append(.artistIs(artist))
        }
        switch releaseOption {
        case .any: break
        case .decade: conditions.append(.releasedInDecade(releaseDecade))
        case .year: conditions.append(.releasedInYear(releaseYear))
        }
        // With a Source Playlist chosen, First Seen is read for that playlist, so
        // "My Shazam Tracks" plus "First Seen in 2026" means "Shazamed in 2026".
        switch firstSeenOption {
        case .any: break
        case .year: conditions.append(.firstSeen(.year(firstSeenYear), in: source))
        case .between: conditions.append(.firstSeen(.between(firstDay: firstSeenFirstDay, lastDay: firstSeenLastDay), in: source))
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
                Section {
                    Toggle("Play Count", isOn: $requiresPlayCount)
                    if requiresPlayCount {
                        Stepper(
                            "Played at least \(minimumPlayCount) times",
                            value: $minimumPlayCount,
                            in: 1...9_999
                        )
                    }
                    Picker("Source Playlist", selection: $source) {
                        Text("Any").tag(SourcePlaylist?.none)
                        ForEach(SourcePlaylist.allCases, id: \.self) { source in
                            Text(source.displayName).tag(SourcePlaylist?.some(source))
                        }
                    }
                    TextField("Genre (any)", text: $genre)
                        .autocorrectionDisabled()
                    TextField("Artist (any)", text: $artist)
                        .autocorrectionDisabled()
                    Picker("Released", selection: $releaseOption) {
                        Text("Any Time").tag(ReleaseOption.any)
                        Text("In a Decade").tag(ReleaseOption.decade)
                        Text("In a Year").tag(ReleaseOption.year)
                    }
                    switch releaseOption {
                    case .any:
                        EmptyView()
                    case .decade:
                        Stepper(
                            "The \(String(releaseDecade))s",
                            value: $releaseDecade,
                            in: 1900...(Self.latestYear / 10 * 10),
                            step: 10
                        )
                    case .year:
                        Stepper(
                            "In \(String(releaseYear))",
                            value: $releaseYear,
                            in: 1900...Self.latestYear
                        )
                    }
                    Picker("First Seen", selection: $firstSeenOption) {
                        Text("Any Time").tag(FirstSeenOption.any)
                        Text("In a Year").tag(FirstSeenOption.year)
                        Text("Between Dates").tag(FirstSeenOption.between)
                    }
                    switch firstSeenOption {
                    case .any:
                        EmptyView()
                    case .year:
                        Stepper(
                            "In \(String(firstSeenYear))",
                            value: $firstSeenYear,
                            in: 2000...Self.latestYear
                        )
                    case .between:
                        DatePicker("From", selection: $firstSeenFirstDay, displayedComponents: .date)
                            .onChange(of: firstSeenFirstDay) {
                                firstSeenLastDay = max(firstSeenLastDay, firstSeenFirstDay)
                            }
                        DatePicker("To", selection: $firstSeenLastDay, in: firstSeenFirstDay..., displayedComponents: .date)
                    }
                } header: {
                    Text("Conditions")
                } footer: {
                    // ADR 0001: Sorted Playlists can only grow, so ranked or relative
                    // Conditions would leave stale Songs behind.
                    Text("A Song must meet every Condition. Conditions are limited to ones a Song can't stop meeting, so there's no \"top 25\" or \"recently played\": MusicSorter can't take Songs back out of a Sorted Playlist.")
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
                    // A Rule with no Conditions would place every Song, for good.
                    .disabled(trimmedName.isEmpty || conditions.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NewRuleView()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
