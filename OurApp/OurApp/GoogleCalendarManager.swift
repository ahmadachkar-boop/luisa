import Foundation
import SwiftUI

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
                Task {
                    try? await syncEvents()
                }
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
        if let user = GIDSignIn.sharedInstance.currentUser {
            isSignedIn = user.grantedScopes?.contains("https://www.googleapis.com/auth/calendar") ?? false
        } else {
            isSignedIn = false
        }
    }

    func signIn() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GoogleCalendarError.noViewController
        }

        // Google Cloud OAuth Client ID
        let clientID = "147528790359-oj9snngdl2msc8p6qtpkte5u21ausvh0.apps.googleusercontent.com"

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
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        lastSyncDate = nil
        ourAppCalendarId = nil
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: "ourAppCalendarId")
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
        let googleEvents = try await fetchGoogleCalendarEvents(
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

        // Update existing synced events
        for event in localEvents where event.googleCalendarId != nil {
            if let lastSynced = event.lastSyncedAt,
               event.date > lastSynced {
                try await updateEventInGoogle(event, calendarId: calendarId, googleEventId: event.googleCalendarId!, user: user)
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

        // Format dates for API (RFC3339)
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: startDate)
        let timeMax = formatter.string(from: endDate)

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleCalendarError.apiError("Failed to fetch events")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
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
}

// MARK: - Errors

enum GoogleCalendarError: LocalizedError {
    case notSignedIn
    case noViewController
    case syncFailed
    case apiError(String)

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
