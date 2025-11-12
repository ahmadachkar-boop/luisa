import ActivityKit
import Foundation

// MARK: - Event Activity Attributes
struct EventActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic content that changes during the Live Activity
        var eventTitle: String
        var countdown: String
        var eventDate: Date
        var isSpecial: Bool
        var currentIndex: Int
        var totalEvents: Int
    }

    // Static content that doesn't change
    var eventId: String
}
