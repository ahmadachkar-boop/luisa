import ActivityKit
import Foundation

@available(iOS 16.1, *)
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<EventActivityAttributes>?
    @Published var currentEventIndex = 0

    private init() {}

    // Start or update the Live Activity with upcoming events
    func updateLiveActivity(with events: [CalendarEvent]) {
        guard !events.isEmpty else {
            endLiveActivity()
            return
        }

        let eventsToShow = Array(events.prefix(5))
        guard currentEventIndex < eventsToShow.count else {
            currentEventIndex = 0
            return
        }

        let event = eventsToShow[currentEventIndex]
        let countdown = countdownText(for: event)

        let contentState = EventActivityAttributes.ContentState(
            eventTitle: event.title,
            countdown: countdown,
            eventDate: event.date,
            isSpecial: event.isSpecial,
            currentIndex: currentEventIndex,
            totalEvents: eventsToShow.count
        )

        if let activity = currentActivity {
            // Update existing activity
            Task {
                await activity.update(using: contentState)
            }
        } else {
            // Start new activity
            let attributes = EventActivityAttributes(eventId: event.id ?? UUID().uuidString)

            do {
                let activity = try Activity<EventActivityAttributes>.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil
                )
                currentActivity = activity
            } catch {
                print("❌ Failed to start Live Activity: \(error)")
            }
        }
    }

    // Navigate to next event
    func nextEvent(events: [CalendarEvent]) {
        let eventsToShow = Array(events.prefix(5))
        if currentEventIndex < eventsToShow.count - 1 {
            currentEventIndex += 1
            updateLiveActivity(with: events)
        }
    }

    // Navigate to previous event
    func previousEvent(events: [CalendarEvent]) {
        if currentEventIndex > 0 {
            currentEventIndex -= 1
            updateLiveActivity(with: events)
        }
    }

    // End the Live Activity
    func endLiveActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(dismissalPolicy: .immediate)
            currentActivity = nil
            currentEventIndex = 0
        }
    }

    // Helper function to calculate countdown text
    private func countdownText(for event: CalendarEvent) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: event.date)

        if let days = components.day, let hours = components.hour, let minutes = components.minute {
            if days > 1 {
                return "\(days)d"
            } else if days == 1 {
                return "1d"
            } else if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
        return ""
    }

    // Check if Live Activities are supported
    static var isSupported: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }
}
