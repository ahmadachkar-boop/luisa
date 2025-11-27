import Foundation
import FirebaseFirestore

// MARK: - Voice Message Model
struct VoiceMessage: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var title: String
    var duration: TimeInterval
    var createdAt: Date
    var audioURL: String
    var fromUser: String
    var folderId: String? // Reference to custom folder
    var isFavorite: Bool? // Whether the memo is marked as favorite

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case createdAt
        case audioURL
        case fromUser
        case folderId
        case isFavorite
    }
}

// MARK: - Voice Memo Folder Model
struct VoiceMemoFolder: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date
    var forUser: String // "Ahmad" or "Luisa" - which user's memos this folder is for

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case forUser
    }
}

// MARK: - Photo Model
struct Photo: Identifiable, Codable {
    @DocumentID var id: String?
    var imageURL: String
    var caption: String
    var uploadedBy: String
    var createdAt: Date // When uploaded
    var capturedAt: Date? // Original date from image metadata (falls back to createdAt if unavailable)
    var eventId: String? // Reference to calendar event if photo is linked to an event
    var folderId: String? // Reference to custom folder if photo is in a folder
    var isFavorite: Bool? // Whether the photo is marked as favorite

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL
        case caption
        case uploadedBy
        case createdAt
        case capturedAt
        case eventId
        case folderId
        case isFavorite
    }
}

// MARK: - Folder Model
struct PhotoFolder: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date
    var type: FolderType // System folders vs custom folders
    var eventId: String? // If this is an event folder, link to the event
    var isSpecialEvent: Bool? // If this is a special event folder

    enum FolderType: String, Codable {
        case allPhotos = "all_photos" // Virtual folder - shows all photos
        case events = "events" // Virtual parent folder for all event folders
        case specialEvents = "special_events" // Virtual parent folder for special event folders
        case eventFolder = "event_folder" // Individual event folder
        case custom = "custom" // User-created folder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case type
        case eventId
        case isSpecialEvent
    }
}

// MARK: - Calendar Event Model
struct CalendarEvent: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var date: Date // Start date
    var endDate: Date? // End date for multi-day events (nil = single day)
    var location: String
    var createdBy: String
    var isSpecial: Bool // For marking special dates
    var photoURLs: [String] // Photos attached to this event
    var googleCalendarId: String? // Google Calendar event ID for synced events
    var lastSyncedAt: Date? // Last time this event was synced with Google Calendar
    var backgroundImageURL: String? // Custom background image for event card
    var backgroundOffsetX: Double? // X offset for background positioning
    var backgroundOffsetY: Double? // Y offset for background positioning
    var backgroundScale: Double? // Scale factor for background image
    var tags: [String]? // Tags for categorizing and filtering events
    var weatherForecast: String? // Weather forecast for the event (cached)

    // Computed property to check if event spans multiple days
    var isMultiDay: Bool {
        guard let endDate = endDate else { return false }
        return !Calendar.current.isDate(date, inSameDayAs: endDate)
    }

    // Get the number of days for the event
    var durationDays: Int {
        guard let endDate = endDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: date, to: endDate).day ?? 0
        return max(1, days + 1)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case date
        case endDate
        case location
        case createdBy
        case isSpecial
        case photoURLs
        case googleCalendarId
        case lastSyncedAt
        case backgroundImageURL
        case backgroundOffsetX
        case backgroundOffsetY
        case backgroundScale
        case tags
        case weatherForecast
    }
}

// MARK: - Wish List Item Model
struct WishListItem: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var addedBy: String
    var createdAt: Date
    var isCompleted: Bool
    var completedDate: Date?
    var category: String // e.g., "Place to Visit", "Activity", "Restaurant", "Experience"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case addedBy
        case createdAt
        case isCompleted
        case completedDate
        case category
    }
}
