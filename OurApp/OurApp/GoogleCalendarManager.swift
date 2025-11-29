import Foundation
import SwiftUI
import FirebaseAuth

/*
 SETUP REQUIRED:

 1. Add Google Sign-In SDK via Swift Package Manager:
    - In Xcode: File > Add Package Dependencies
    - URL: https://github.com/google/GoogleSignIn-iOS
    - Version: 7.0.0 or later

 2. Set up Google Cloud Project:
    - Go to: https://console.cloud.google.com
    - Create a new project or select existing
    - Enable Google Calendar API
    - Create OAuth 2.0 Client ID (iOS)
    - Download the Client ID (looks like: XXXXXXXXXX-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com)

 3. Add URL scheme to Info.plist:
    - Key: URL types
    - Add your reversed client ID as URL scheme

 4. Add your Client ID to the signIn() method below

 This implementation uses URLSession for direct REST API calls to Google Calendar,
 so you don't need the GoogleAPIClientForREST library.
 */

import GoogleSignIn

@MainActor
class GoogleCalendarManager: ObservableObject {
    static let shared = GoogleCalendarManager()

    @Published var isSignedIn = false
    @Published var isSyncing = false
    @Published var autoSyncEnabled = false {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "googleCalendarAutoSync")
            if autoSyncEnabled {
                startPeriodicSync()
            } else {
                stopPeriodicSync()
            }
        }
    }
    @Published var syncUpcoming = true {
        didSet {
            UserDefaults.standard.set(syncUpcoming, forKey: "syncUpcoming")
        }
    }
    @Published var syncPast = false {
        didSet {
            UserDefaults.standard.set(syncPast, forKey: "syncPast")
        }
    }
    @Published var lastSyncDate: Date?
    @Published var ourAppCalendarId: String?

    private let firebaseManager = FirebaseManager.shared
    private let ourAppCalendarName = "OurApp"
    private var periodicSyncTimer: Timer?
    private let syncInterval: TimeInterval = 30 * 60 // 30 minutes

    // Incremental sync support
    private var syncToken: String? {
        get { UserDefaults.standard.string(forKey: "googleCalendarSyncToken") }
        set { UserDefaults.standard.set(newValue, forKey: "googleCalendarSyncToken") }
    }

    private init() {
        // Load saved preferences
        autoSyncEnabled = UserDefaults.standard.bool(forKey: "googleCalendarAutoSync")
        syncUpcoming = UserDefaults.standard.bool(forKey: "syncUpcoming")
        syncPast = UserDefaults.standard.bool(forKey: "syncPast")
        ourAppCalendarId = UserDefaults.standard.string(forKey: "ourAppCalendarId")

        if let lastSync = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
            lastSyncDate = lastSync
        }

        checkSignInStatus()
    }

    // MARK: - Authentication

    func checkSignInStatus() {
        // Try to restore previous sign-in
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    print("⚠️ [GOOGLE SIGN-IN] Failed to restore previous sign-in: \(error.localizedDescription)")
                    self.isSignedIn = false
                    return
                }

                if let user = user {
                    let hasCalendarScope = user.grantedScopes?.contains("https://www.googleapis.com/auth/calendar") ?? false
                    self.isSignedIn = hasCalendarScope

                    if hasCalendarScope {
                        print("✅ [GOOGLE SIGN-IN] Restored previous sign-in session")
                        // Verify we still have the calendar ID
                        if self.ourAppCalendarId != nil {
                            print("✅ [GOOGLE CALENDAR] Found existing OurApp calendar ID")
                        }

                        // Start periodic sync if auto-sync is enabled AND Firebase auth is complete
                        if self.autoSyncEnabled {
                            if Auth.auth().currentUser != nil {
                                print("🔄 [GOOGLE SYNC] Auto-sync enabled, starting periodic sync")
                                self.startPeriodicSync()
                            } else {
                                print("⚠️ [GOOGLE SYNC] Auto-sync enabled but waiting for phone auth")
                            }
                        }
                    } else {
                        print("⚠️ [GOOGLE SIGN-IN] Restored user but missing calendar scope")
                        self.isSignedIn = false
                    }
                } else {
                    self.isSignedIn = false
                }
            }
        }
    }

    func signIn() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GoogleCalendarError.noViewController
        }

        // Read Google Cloud OAuth Client ID from Info.plist
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw GoogleCalendarError.missingConfiguration("GIDClientID not found in Info.plist")
        }

        let signInConfig = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = signInConfig

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/calendar"]
        )

        isSignedIn = true

        // Find or create the OurApp calendar
        try await findOrCreateOurAppCalendar(user: result.user)

        // Start periodic sync if auto-sync is enabled
        if autoSyncEnabled {
            startPeriodicSync()
        }
    }

    func signOut() {
        stopPeriodicSync()
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        lastSyncDate = nil
        ourAppCalendarId = nil
        syncToken = nil // Clear sync token for fresh start on next sign-in
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: "ourAppCalendarId")
        UserDefaults.standard.removeObject(forKey: "googleCalendarSyncToken")
    }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        // Stop any existing timer
        stopPeriodicSync()

        guard isSignedIn else {
            print("⚠️ [GOOGLE SYNC] Cannot start periodic sync - not signed in")
            return
        }

        print("🔄 [GOOGLE SYNC] Starting periodic sync (every \(Int(syncInterval / 60)) minutes)")

        // Sync immediately on start
        Task {
            do {
                try await syncEvents()
                print("✅ [GOOGLE SYNC] Initial sync completed")
            } catch {
                print("⚠️ [GOOGLE SYNC] Initial sync failed: \(error.localizedDescription)")
            }
        }

        // Start periodic timer
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSignedIn, self.autoSyncEnabled else { return }

                do {
                    print("🔄 [GOOGLE SYNC] Running periodic sync...")
                    try await self.syncEvents()
                    print("✅ [GOOGLE SYNC] Periodic sync completed")
                } catch {
                    print("⚠️ [GOOGLE SYNC] Periodic sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
        print("⏹️ [GOOGLE SYNC] Stopped periodic sync")
    }

    // MARK: - App Lifecycle Handlers

    func handleAppBecameActive() async {
        guard isSignedIn, autoSyncEnabled else { return }

        // Check if we should sync based on last sync time
        let shouldSync: Bool
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            // Sync if it's been more than 5 minutes since last sync
            shouldSync = timeSinceLastSync > (5 * 60)
        } else {
            shouldSync = true
        }

        if shouldSync {
            print("🔄 [GOOGLE SYNC] App became active, running sync...")
            do {
                try await syncEvents()
                print("✅ [GOOGLE SYNC] App activation sync completed")
            } catch {
                print("⚠️ [GOOGLE SYNC] App activation sync failed: \(error.localizedDescription)")
            }
        } else {
            print("⏭️ [GOOGLE SYNC] Skipping sync, recently synced")
        }

        // Restart the periodic timer
        startPeriodicSync()
    }

    func handleAppEnteredBackground() {
        stopPeriodicSync()
    }

    /// Called when Firebase phone auth is completed to start sync if ready
    func onPhoneAuthCompleted() {
        guard isSignedIn, autoSyncEnabled else {
            print("⚠️ [GOOGLE SYNC] Phone auth completed but Google not signed in or auto-sync disabled")
            return
        }

        print("🔄 [GOOGLE SYNC] Phone auth completed, starting sync...")
        startPeriodicSync()
    }

    // MARK: - Calendar Management

    private func findOrCreateOurAppCalendar(user: GIDGoogleUser) async throws {
        try await refreshTokenIfNeeded(user: user)
        let accessToken = user.accessToken.tokenString

        // First, try to find existing OurApp calendar
        let listURL = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        var listRequest = URLRequest(url: listURL)
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)

        guard let httpResponse = listResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to fetch calendar list")
        }

        if let json = try JSONSerialization.jsonObject(with: listData) as? [String: Any],
           let items = json["items"] as? [[String: Any]] {
            // Look for existing OurApp calendar
            for item in items {
                if let summary = item["summary"] as? String,
                   summary == ourAppCalendarName,
                   let calendarId = item["id"] as? String {
                    // Found existing calendar
                    ourAppCalendarId = calendarId
                    UserDefaults.standard.set(calendarId, forKey: "ourAppCalendarId")
                    print("✅ Found existing OurApp calendar: \(calendarId)")
                    return
                }
            }
        }

        // Calendar doesn't exist, create it
        let createURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let calendarBody: [String: Any] = [
            "summary": ourAppCalendarName,
            "description": "Events synced from OurApp",
            "timeZone": TimeZone.current.identifier
        ]

        createRequest.httpBody = try JSONSerialization.data(withJSONObject: calendarBody)

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)

        guard let createHttpResponse = createResponse as? HTTPURLResponse,
              createHttpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to create OurApp calendar")
        }

        guard let createJson = try JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let calendarId = createJson["id"] as? String else {
            throw GoogleCalendarError.apiError("Invalid response when creating calendar")
        }

        ourAppCalendarId = calendarId
        UserDefaults.standard.set(calendarId, forKey: "ourAppCalendarId")
        print("✅ Created new OurApp calendar: \(calendarId)")
    }

    // MARK: - Sync Operations

    func syncEvents() async throws {
        guard isSignedIn else {
            throw GoogleCalendarError.notSignedIn
        }

        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarError.notSignedIn
        }

        // Check if user is authenticated with Firebase (phone auth)
        guard Auth.auth().currentUser != nil else {
            print("⚠️ [GOOGLE SYNC] Cannot sync - Firebase phone auth not completed")
            throw GoogleCalendarError.apiError("Please complete phone authentication first")
        }

        // Refresh access token if needed
        try await refreshTokenIfNeeded(user: user)

        // Ensure OurApp calendar exists
        if ourAppCalendarId == nil {
            try await findOrCreateOurAppCalendar(user: user)
        }

        guard let calendarId = ourAppCalendarId else {
            throw GoogleCalendarError.apiError("OurApp calendar not found")
        }

        isSyncing = true
        defer { isSyncing = false }

        // Fetch all local events from Firebase
        let localEvents = try await firebaseManager.fetchAllEvents()

        // Determine sync time range
        let calendar = Calendar.current
        var dateComponents = DateComponents()

        let startDate: Date
        if syncPast {
            dateComponents.year = -1
            startDate = calendar.date(byAdding: dateComponents, to: Date()) ?? Date()
        } else {
            startDate = Date()
        }

        let endDate: Date
        if syncUpcoming {
            dateComponents.year = 1
            endDate = calendar.date(byAdding: dateComponents, to: Date()) ?? Date()
        } else {
            endDate = Date()
        }

        // Fetch events from Google Calendar
        _ = try await fetchGoogleCalendarEvents(
            user: user,
            calendarId: calendarId,
            startDate: startDate,
            endDate: endDate
        )

        // Upload new local events to Google Calendar
        for event in localEvents where event.googleCalendarId == nil {
            if (syncUpcoming && event.date >= Date()) || (syncPast && event.date < Date()) {
                let googleEventId = try await uploadEventToGoogle(event, calendarId: calendarId, user: user)
                // Update local event with Google Calendar ID
                var updatedEvent = event
                updatedEvent.googleCalendarId = googleEventId
                updatedEvent.lastSyncedAt = Date()
                try await firebaseManager.updateEvent(updatedEvent)
            }
        }

        // Update existing synced events that have been modified since last sync
        for event in localEvents where event.googleCalendarId != nil {
            // Check if event was modified after last sync using updatedAt timestamp
            if let lastSynced = event.lastSyncedAt,
               let updatedAt = event.updatedAt,
               updatedAt > lastSynced {
                try await updateEventInGoogle(event, calendarId: calendarId, googleEventId: event.googleCalendarId!, user: user)
                // Update lastSyncedAt after successful sync
                var syncedEvent = event
                syncedEvent.lastSyncedAt = Date()
                try? await firebaseManager.updateEvent(syncedEvent)
            }
        }

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }

    private func refreshTokenIfNeeded(user: GIDGoogleUser) async throws {
        if user.accessToken.expirationDate?.timeIntervalSinceNow ?? 0 < 300 {
            try await user.refreshTokensIfNeeded()
        }
    }

    private func fetchGoogleCalendarEvents(user: GIDGoogleUser, calendarId: String, startDate: Date, endDate: Date) async throws -> [[String: Any]] {
        let accessToken = user.accessToken.tokenString
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events")!

        // Try incremental sync if we have a sync token
        if let token = syncToken {
            print("🔄 [GOOGLE SYNC] Using incremental sync with token")
            components.queryItems = [
                URLQueryItem(name: "syncToken", value: token)
            ]
        } else {
            // Full sync - use date range
            print("🔄 [GOOGLE SYNC] Performing full sync (no token)")
            let formatter = ISO8601DateFormatter()
            let timeMin = formatter.string(from: startDate)
            let timeMax = formatter.string(from: endDate)

            components.queryItems = [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime")
            ]
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarError.apiError("Invalid response")
        }

        // Handle 410 Gone - sync token expired, need full sync
        if httpResponse.statusCode == 410 {
            print("⚠️ [GOOGLE SYNC] Sync token expired, clearing and retrying full sync")
            syncToken = nil
            return try await fetchGoogleCalendarEvents(user: user, calendarId: calendarId, startDate: startDate, endDate: endDate)
        }

        guard httpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to fetch events (status: \(httpResponse.statusCode))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Store the new sync token for next incremental sync
        if let newSyncToken = json["nextSyncToken"] as? String {
            syncToken = newSyncToken
            print("✅ [GOOGLE SYNC] Stored new sync token for incremental sync")
        }

        // Handle pagination if there's a nextPageToken
        var allItems = json["items"] as? [[String: Any]] ?? []

        if let nextPageToken = json["nextPageToken"] as? String {
            let moreItems = try await fetchNextPage(user: user, calendarId: calendarId, pageToken: nextPageToken)
            allItems.append(contentsOf: moreItems)
        }

        let itemCount = allItems.count
        if itemCount > 0 {
            print("📅 [GOOGLE SYNC] Fetched \(itemCount) events")
        } else {
            print("📅 [GOOGLE SYNC] No new/changed events")
        }

        return allItems
    }

    private func fetchNextPage(user: GIDGoogleUser, calendarId: String, pageToken: String) async throws -> [[String: Any]] {
        let accessToken = user.accessToken.tokenString
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events")!
        components.queryItems = [URLQueryItem(name: "pageToken", value: pageToken)]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Store the sync token if this is the last page
        if let newSyncToken = json["nextSyncToken"] as? String {
            syncToken = newSyncToken
        }

        var items = json["items"] as? [[String: Any]] ?? []

        // Continue pagination if needed
        if let nextToken = json["nextPageToken"] as? String {
            let moreItems = try await fetchNextPage(user: user, calendarId: calendarId, pageToken: nextToken)
            items.append(contentsOf: moreItems)
        }

        return items
    }

    func uploadEventToGoogle(_ event: CalendarEvent, calendarId: String, user: GIDGoogleUser) async throws -> String {
        let accessToken = user.accessToken.tokenString

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create event body
        let formatter = ISO8601DateFormatter()
        let eventBody: [String: Any] = [
            "summary": event.title,
            "description": event.description,
            "location": event.location,
            "start": [
                "dateTime": formatter.string(from: event.date),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: event.date.addingTimeInterval(3600)), // 1 hour default
                "timeZone": TimeZone.current.identifier
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to create event")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventId = json["id"] as? String else {
            throw GoogleCalendarError.apiError("Invalid response")
        }

        return eventId
    }

    func deleteEventFromGoogle(_ googleEventId: String, calendarId: String? = nil, user: GIDGoogleUser? = nil) async throws {
        let user = user ?? GIDSignIn.sharedInstance.currentUser
        guard let user = user else {
            throw GoogleCalendarError.notSignedIn
        }

        let calId = calendarId ?? ourAppCalendarId ?? "primary"

        try await refreshTokenIfNeeded(user: user)
        let accessToken = user.accessToken.tokenString

        let encodedCalendarId = calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events/\(googleEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw GoogleCalendarError.apiError("Failed to delete event")
        }
    }

    func updateEventInGoogle(_ event: CalendarEvent, calendarId: String, googleEventId: String, user: GIDGoogleUser? = nil) async throws {
        let user = user ?? GIDSignIn.sharedInstance.currentUser
        guard let user = user else {
            throw GoogleCalendarError.notSignedIn
        }

        try await refreshTokenIfNeeded(user: user)
        let accessToken = user.accessToken.tokenString

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events/\(googleEventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create event body
        let formatter = ISO8601DateFormatter()
        let eventBody: [String: Any] = [
            "summary": event.title,
            "description": event.description,
            "location": event.location,
            "start": [
                "dateTime": formatter.string(from: event.date),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: event.date.addingTimeInterval(3600)),
                "timeZone": TimeZone.current.identifier
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to update event")
        }
    }

    // MARK: - Cleanup

    func cleanupDuplicateEvents() async throws -> Int {
        guard isSignedIn else {
            throw GoogleCalendarError.notSignedIn
        }

        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarError.notSignedIn
        }

        guard let calendarId = ourAppCalendarId else {
            throw GoogleCalendarError.apiError("OurApp calendar not found")
        }

        try await refreshTokenIfNeeded(user: user)

        // Fetch events in smaller chunks to reduce memory usage
        // Check 6 months past + 6 months future (reduced from 3 years)
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let endDate = calendar.date(byAdding: .month, value: 6, to: Date()) ?? Date()

        print("🔍 [GOOGLE CLEANUP] Checking events from \(startDate) to \(endDate)")

        let events = try await fetchGoogleCalendarEvents(
            user: user,
            calendarId: calendarId,
            startDate: startDate,
            endDate: endDate
        )

        print("📊 [GOOGLE CLEANUP] Found \(events.count) events to check for duplicates")

        // Group events by title and start date
        var eventGroups: [String: [[String: Any]]] = [:]

        for event in events {
            guard let summary = event["summary"] as? String,
                  let start = event["start"] as? [String: Any],
                  let dateTimeString = start["dateTime"] as? String else {
                continue
            }

            // Create a key combining title and date (ignoring time for grouping)
            let key = "\(summary)|\(dateTimeString.prefix(10))"

            if eventGroups[key] == nil {
                eventGroups[key] = []
            }
            eventGroups[key]?.append(event)
        }

        // Delete duplicates (keep first, delete rest)
        var deletedCount = 0

        for (_, group) in eventGroups where group.count > 1 {
            // Skip first event, delete the rest
            for event in group.dropFirst() {
                if let eventId = event["id"] as? String {
                    do {
                        try await deleteGoogleEvent(calendarId: calendarId, eventId: eventId, user: user)
                        deletedCount += 1
                    } catch {
                        print("⚠️ [GOOGLE CLEANUP] Failed to delete duplicate event: \(error)")
                    }
                }
            }
        }

        return deletedCount
    }

    private func deleteGoogleEvent(calendarId: String, eventId: String, user: GIDGoogleUser) async throws {
        let accessToken = user.accessToken.tokenString

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.apiError("Failed to delete event")
        }
    }
}

// MARK: - Errors

enum GoogleCalendarError: LocalizedError {
    case notSignedIn
    case noViewController
    case syncFailed
    case apiError(String)
    case missingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to Google Calendar first"
        case .noViewController:
            return "Could not present sign-in screen"
        case .syncFailed:
            return "Failed to sync with Google Calendar"
        case .apiError(let message):
            return "API Error: \(message)"
        case .missingConfiguration(let message):
            return "Configuration Error: \(message)"
        }
    }
}

// MARK: - Setup Instructions

/*
 DETAILED SETUP STEPS:

 1. Add Swift Package Dependencies:
    In Xcode: File > Add Package Dependencies
    Add Google Sign-In: https://github.com/google/GoogleSignIn-iOS
    Version: 7.0.0 or later

 2. Google Cloud Console Setup:
    a. Go to https://console.cloud.google.com
    b. Create a new project or select existing
    c. Enable APIs:
       - Google Calendar API
       - Google Sign-In API (if available)
    d. Create credentials:
       - Create OAuth 2.0 Client ID
       - Application type: iOS
       - Bundle ID: (use your actual bundle ID from Xcode)
       - Copy the Client ID (format: XXXXXXXXXX-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com)

 3. Configure Xcode Project:
    a. Update the signIn() method above with your Client ID
    b. In Info.plist, add URL scheme:
       <key>CFBundleURLTypes</key>
       <array>
         <dict>
           <key>CFBundleURLSchemes</key>
           <array>
             <string>com.googleusercontent.apps.YOUR-CLIENT-ID-HERE</string>
           </array>
         </dict>
       </array>
    c. Update OurAppApp.swift to handle URL:
       import GoogleSignIn

       .onOpenURL { url in
           GIDSignIn.sharedInstance.handle(url)
       }

 4. Test the Integration:
    - Build and run the app
    - Go to Settings tab
    - Tap "Connect Google Calendar"
    - Sign in with Google account
    - Grant calendar permissions
    - Try "Sync Now" to test
 */
