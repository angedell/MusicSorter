//
//  RuleEditorView.swift
//  MusicSorter
//

import SwiftData
import SwiftUI

/// Creates a Rule from any combination of Conditions: play count, Source Playlist, genre,
/// artist, release decade or year and First Seen. The Rule can be made a Grouped Rule.
///
/// Given a Rule, edits its name and Conditions instead; its Grouping can't be changed.
struct RuleEditorView: View {
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

    /// What the Rule groups by, if it's a Grouped Rule.
    private enum GroupingOption: Hashable {
        case none
        case primaryGenre
        case artist
        case releaseDecade
        case firstSeenYear
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
    /// The time zone First Seen is read in. An edited Rule keeps its own, so an unchanged
    /// First Seen Condition stays the same after the user travels (ADR 0001).
    @State private var firstSeenTimeZone = TimeZone.current
    @State private var groupingOption = GroupingOption.none
    @State private var groupThreshold = 5
    @State private var isConfirmingTightening = false

    /// The Rule being edited, or `nil` when adding one.
    private let rule: Rule?

    init(rule: Rule? = nil) {
        self.rule = rule
        guard let rule else { return }
        _name = State(initialValue: rule.name)
        _requiresPlayCount = State(initialValue: false)
        // Each kind of Condition appears at most once, as this view creates them.
        for condition in rule.conditions {
            switch condition {
            case .playCountAtLeast(let count):
                _requiresPlayCount = State(initialValue: true)
                _minimumPlayCount = State(initialValue: count)
            case .sourcePlaylistIs(let source):
                _source = State(initialValue: source)
            case .genreIs(let genre):
                _genre = State(initialValue: genre)
            case .artistIs(let artist):
                _artist = State(initialValue: artist)
            case .releasedInYear(let year):
                _releaseOption = State(initialValue: .year)
                _releaseYear = State(initialValue: year)
            case .releasedInDecade(let decade):
                _releaseOption = State(initialValue: .decade)
                _releaseDecade = State(initialValue: decade)
            case .firstSeen(let period, _):
                _firstSeenTimeZone = State(initialValue: period.timeZone)
                switch period.span {
                case .year(let year):
                    _firstSeenOption = State(initialValue: .year)
                    _firstSeenYear = State(initialValue: year)
                case .between(let firstDay, let lastDay):
                    _firstSeenOption = State(initialValue: .between)
                    _firstSeenFirstDay = State(initialValue: firstDay)
                    _firstSeenLastDay = State(initialValue: lastDay)
                }
            }
        }
    }

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
        case .year: conditions.append(.firstSeen(.year(firstSeenYear, in: firstSeenTimeZone), in: source))
        case .between: conditions.append(.firstSeen(.between(firstDay: firstSeenFirstDay, lastDay: firstSeenLastDay, in: firstSeenTimeZone), in: source))
        }
        return conditions
    }

    private var canSave: Bool {
        // Stored Conditions that can't be read open as none, and mustn't be overwritten.
        if let rule, rule.storedConditions == nil { return false }
        // A Rule with no Conditions would place every Song, for good. A Grouped Rule may
        // have none: it files every Song into its Group.
        return !trimmedName.isEmpty && !(conditions.isEmpty && grouping == nil)
    }

    private var grouping: Grouping? {
        if let rule { return rule.grouping }
        return switch groupingOption {
        case .none: nil
        case .primaryGenre: .primaryGenre
        case .artist: .artist
        case .releaseDecade: .releaseDecade
        // As with the First Seen Condition, a chosen Source Playlist's First Seen is used.
        case .firstSeenYear: .firstSeenYear(in: source)
        }
    }

    private var playlistNameFooter: String {
        if let rule {
            if rule.isGrouped {
                return "Each group's Sorted Playlist is called by the group."
            }
            if rule.currentSortedPlaylist != nil {
                return "Renaming doesn't rename the Sorted Playlist already in Music. Start over in a new playlist to get one with the new name."
            }
        }
        return switch groupingOption {
        case .none:
            "The Sorted Playlist will be called \"\(Rule.sortedPlaylistName(for: trimmedName.isEmpty ? "Name" : trimmedName))\"."
        case .primaryGenre:
            "Each genre's Sorted Playlist will be called by the genre, e.g. \"\(Rule.sortedPlaylistName(for: "Jazz"))\"."
        case .artist:
            "Each artist's Sorted Playlist will be called by the artist, e.g. \"\(Rule.sortedPlaylistName(for: "Daft Punk"))\"."
        case .releaseDecade:
            "Each decade's Sorted Playlist will be called by the decade, e.g. \"\(Rule.sortedPlaylistName(for: "1990s"))\"."
        case .firstSeenYear:
            "Each year's Sorted Playlist will be called by the year, e.g. \"\(Rule.sortedPlaylistName(for: "2026"))\"."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text(playlistNameFooter)
                }
                if let rule {
                    if let grouping = rule.grouping {
                        Section {
                            Text(grouping.summary)
                            Text("At least \(rule.groupThreshold) songs per group")
                        } header: {
                            Text("Grouping")
                        }
                    }
                } else {
                    groupingSection
                }
                conditionsSection
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(rule == nil ? "Add" : "Save", role: .confirm) {
                        if let rule, rule.canStartOver,
                           Rule.isTightening(from: rule.conditions, to: conditions) {
                            isConfirmingTightening = true
                        } else {
                            save(startingOver: false)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            // ADR 0001: a tightened Rule can't take Songs back out of its Sorted Playlist.
            .confirmationDialog(
                "Songs already sorted will stay",
                isPresented: $isConfirmingTightening,
                titleVisibility: .visible
            ) {
                Button("Save") { save(startingOver: false) }
                Button("Save and Start Over in a New Playlist") { save(startingOver: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("MusicSorter can't remove Songs from a Sorted Playlist, so Songs that no longer meet this Rule stay where they are. Start over to get a new playlist with only the Songs that meet it now.")
            }
        }
    }

    private func save(startingOver: Bool) {
        if let rule {
            rule.name = trimmedName
            rule.conditions = conditions
            if startingOver {
                rule.startOver()
            }
        } else {
            modelContext.insert(Rule(
                name: trimmedName,
                conditions: conditions,
                grouping: grouping,
                groupThreshold: groupThreshold,
                createdAt: .now
            ))
        }
        dismiss()
    }

    private var groupingSection: some View {
        Section {
            Picker("Group By", selection: $groupingOption) {
                Text("None").tag(GroupingOption.none)
                Text("Genre").tag(GroupingOption.primaryGenre)
                Text("Artist").tag(GroupingOption.artist)
                Text("Release Decade").tag(GroupingOption.releaseDecade)
                Text("Year First Seen").tag(GroupingOption.firstSeenYear)
            }
            if groupingOption != .none {
                Stepper(
                    "At least \(groupThreshold) songs per group",
                    value: $groupThreshold,
                    in: 1...999
                )
            }
        } header: {
            Text("Grouping")
        } footer: {
            if groupingOption != .none {
                Text("A group's Sorted Playlist is created once the group has \(groupThreshold) songs, then grows as more songs join. Songs without a value to group by are left out.")
            }
        }
    }

    private var conditionsSection: some View {
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
}

#Preview {
    RuleEditorView()
        .modelContainer(for: MusicSorterSchema.models, inMemory: true)
}
