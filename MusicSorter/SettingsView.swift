//
//  SettingsView.swift
//  MusicSorter
//

import SwiftUI

/// App settings: the optional summary notification after a background Sorting Run.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(SummaryNotification.isEnabledKey) private var postsSummaryNotification = false
    @State private var wasNotificationPermissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notify After Sorting", isOn: $postsSummaryNotification)
                } footer: {
                    if wasNotificationPermissionDenied {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MusicSorter isn't allowed to send notifications. Turn them on in Settings.")
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            .font(.footnote)
                        }
                    } else {
                        Text("After sorting in the background, MusicSorter tells you how many Songs it placed. Nothing is sent when no Songs were placed.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: postsSummaryNotification) { _, isOn in
                guard isOn else { return }
                Task {
                    let isGranted = await SummaryNotification.requestAuthorization()
                    wasNotificationPermissionDenied = !isGranted
                    // Without permission nothing can be posted, so the setting can't stay on.
                    if !isGranted {
                        postsSummaryNotification = false
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
