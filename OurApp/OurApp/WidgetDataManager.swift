import Foundation
import WidgetKit

// MARK: - Widget Data Manager
// This class syncs events to the widget via App Groups shared UserDefaults

class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let appGroupIdentifier = "group.com.ourapp"
    private let eventsKey = "upcomingEvents"
    private let firebaseManager = FirebaseManager.shared

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private init() {}

    // MARK: - Sync from Firebase (call at app startup)
    func syncFromFirebase() {
        Task {
            do {
                // Get events directly from Firebase (one-time fetch)
                let events = try await firebaseManager.fetchAllEvents()
                await MainActor.run {
                    self.syncEvents(events)
                    print("WidgetDataManager: Synced \(events.count) events from Firebase to widget")
                }
            } catch {
                print("WidgetDataManager: Failed to sync from Firebase: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync Events to Widget
    func syncEvents(_ events: [CalendarEvent]) {
        guard let sharedDefaults = sharedDefaults else {
            print("WidgetDataManager: Unable to access shared UserDefaults")
            return
        }

        // Filter to upcoming events only, sorted by date
        // Use start of today to include all of today's events (matches CalendarView behavior)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let upcomingEvents = events
            .filter { $0.date >= startOfToday }
            .sorted { $0.date < $1.date }
            .prefix(5) // Keep only the next 5 events
            .map { event in
                WidgetEvent(
                    id: event.id ?? UUID().uuidString,
                    title: event.title,
                    date: event.date,
                    location: event.location,
                    isSpecial: event.isSpecial
                )
            }

        // Encode and save to shared UserDefaults
        if let encoded = try? JSONEncoder().encode(Array(upcomingEvents)) {
            sharedDefaults.set(encoded, forKey: eventsKey)
            sharedDefaults.synchronize()

            // Reload widget timeline
            WidgetCenter.shared.reloadTimelines(ofKind: "CountdownWidget")
        }
    }

    // MARK: - Clear Widget Data
    func clearWidgetData() {
        sharedDefaults?.removeObject(forKey: eventsKey)
        sharedDefaults?.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "CountdownWidget")
    }

    // MARK: - Force Reload Widget
    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CountdownWidget")
    }
}

// MARK: - Widget Event Model (matches the widget's model)
struct WidgetEvent: Codable {
    let id: String
    let title: String
    let date: Date
    let location: String
    let isSpecial: Bool
}
