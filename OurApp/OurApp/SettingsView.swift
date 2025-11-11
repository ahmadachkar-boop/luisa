import SwiftUI

struct SettingsView: View {
    @StateObject private var googleCalendarManager = GoogleCalendarManager.shared
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""

    var body: some View {
        NavigationView {
            List {
                // Google Calendar Integration Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Calendar")
                                .font(.headline)

                            if googleCalendarManager.isSignedIn {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Not connected")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        Spacer()

                        Image(systemName: "calendar.badge.checkmark")
                            .font(.title2)
                            .foregroundColor(googleCalendarManager.isSignedIn ? .green : Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    if googleCalendarManager.isSignedIn {
                        Button(action: {
                            Task {
                                await syncWithGoogleCalendar()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                                Spacer()
                                if googleCalendarManager.isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(googleCalendarManager.isSyncing)

                        Toggle("Auto-sync", isOn: $googleCalendarManager.autoSyncEnabled)

                        if googleCalendarManager.lastSyncDate != nil {
                            HStack {
                                Text("Last synced")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(googleCalendarManager.lastSyncDate!, format: .relative(presentation: .named))
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }

                        Button(role: .destructive, action: {
                            googleCalendarManager.signOut()
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                Text("Disconnect")
                            }
                        }
                    } else {
                        Button(action: {
                            Task {
                                await signInToGoogle()
                            }
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("Connect Google Calendar")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                } header: {
                    Text("Calendar Integration")
                } footer: {
                    Text("Sync your events with Google Calendar to access them across all your devices.")
                }

                // Sync Settings
                if googleCalendarManager.isSignedIn {
                    Section {
                        Toggle("Sync Upcoming Events", isOn: $googleCalendarManager.syncUpcoming)
                        Toggle("Sync Past Events", isOn: $googleCalendarManager.syncPast)
                    } header: {
                        Text("Sync Options")
                    }
                }

                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.4.0")
                            .foregroundColor(.gray)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .alert("Sync Status", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncAlertMessage)
            }
        }
    }

    func signInToGoogle() async {
        do {
            try await googleCalendarManager.signIn()
            syncAlertMessage = "Successfully connected to Google Calendar!"
            showingSyncAlert = true
        } catch {
            syncAlertMessage = "Failed to connect: \(error.localizedDescription)"
            showingSyncAlert = true
        }
    }

    func syncWithGoogleCalendar() async {
        do {
            try await googleCalendarManager.syncEvents()
            syncAlertMessage = "Events synced successfully!"
            showingSyncAlert = true
        } catch {
            syncAlertMessage = "Sync failed: \(error.localizedDescription)"
            showingSyncAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
