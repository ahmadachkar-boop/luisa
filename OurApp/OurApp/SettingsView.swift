import SwiftUI

struct SettingsView: View {
    @StateObject private var googleCalendarManager = GoogleCalendarManager.shared
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var isCleaningUp = false
    @State private var showingCleanupAlert = false
    @State private var cleanupMessage = ""

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

                // Data Management
                Section {
                    Button(action: {
                        Task {
                            await cleanupOrphanedPhotos()
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash.circle")
                            Text("Clean Up Orphaned Photos")
                            Spacer()
                            if isCleaningUp {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCleaningUp)

                    if googleCalendarManager.isSignedIn {
                        Button(action: {
                            Task {
                                await cleanupDuplicateGoogleEvents()
                            }
                        }) {
                            HStack {
                                Image(systemName: "calendar.badge.exclamationmark")
                                Text("Clean Up Google Calendar Duplicates")
                                Spacer()
                                if googleCalendarManager.isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(googleCalendarManager.isSyncing)
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    if googleCalendarManager.isSignedIn {
                        Text("Remove photo entries that no longer have associated files. Clean up duplicate events in Google Calendar.")
                    } else {
                        Text("Remove photo entries that no longer have associated files. This fixes eternal gray loading screens.")
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
            .alert("Cleanup Complete", isPresented: $showingCleanupAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(cleanupMessage)
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

    func cleanupOrphanedPhotos() async {
        isCleaningUp = true
        defer { isCleaningUp = false }

        do {
            let deletedCount = try await FirebaseManager.shared.cleanupOrphanedPhotos()
            if deletedCount > 0 {
                cleanupMessage = "Successfully removed \(deletedCount) orphaned photo\(deletedCount == 1 ? "" : "s")."
            } else {
                cleanupMessage = "No orphaned photos found. Your photos are all in good shape!"
            }
            showingCleanupAlert = true
        } catch {
            cleanupMessage = "Cleanup failed: \(error.localizedDescription)"
            showingCleanupAlert = true
        }
    }

    func cleanupDuplicateGoogleEvents() async {
        do {
            let deletedCount = try await googleCalendarManager.cleanupDuplicateEvents()
            if deletedCount > 0 {
                cleanupMessage = "Successfully removed \(deletedCount) duplicate event\(deletedCount == 1 ? "" : "s") from Google Calendar."
            } else {
                cleanupMessage = "No duplicate events found. Your Google Calendar is clean!"
            }
            showingCleanupAlert = true
        } catch {
            cleanupMessage = "Cleanup failed: \(error.localizedDescription)"
            showingCleanupAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
