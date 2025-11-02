import Foundation
import FirebaseFirestore

// MARK: - Voice Message Model
struct VoiceMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var duration: TimeInterval
    var createdAt: Date
    var audioURL: String
    var fromUser: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case createdAt
        case audioURL
        case fromUser
    }
}

// MARK: - Photo Model
struct Photo: Identifiable, Codable {
    @DocumentID var id: String?
    var imageURL: String
    var caption: String
    var uploadedBy: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL
        case caption
        case uploadedBy
        case createdAt
    }
}

// MARK: - Calendar Event Model
struct CalendarEvent: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var date: Date
    var location: String
    var createdBy: String
    var isSpecial: Bool // For marking special dates

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case date
        case location
        case createdBy
        case isSpecial
    }
}
