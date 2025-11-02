import Foundation
import FirebaseFirestore
import FirebaseStorage

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    let db = Firestore.firestore()
    let storage = Storage.storage()

    private init() {}

    // MARK: - Voice Messages
    func uploadVoiceMessage(audioData: Data, title: String, duration: TimeInterval, fromUser: String) async throws -> String {
        let fileName = "\(UUID().uuidString).m4a"
        let storageRef = storage.reference().child("voice_messages/\(fileName)")

        let _ = try await storageRef.putDataAsync(audioData)
        let downloadURL = try await storageRef.downloadURL()

        let voiceMessage = VoiceMessage(
            title: title,
            duration: duration,
            createdAt: Date(),
            audioURL: downloadURL.absoluteString,
            fromUser: fromUser
        )

        try db.collection("voiceMessages").addDocument(from: voiceMessage)
        return downloadURL.absoluteString
    }

    func getVoiceMessages() -> AsyncThrowingStream<[VoiceMessage], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("voiceMessages")
                .order(by: "createdAt", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    let messages = documents.compactMap { doc -> VoiceMessage? in
                        try? doc.data(as: VoiceMessage.self)
                    }

                    continuation.yield(messages)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func deleteVoiceMessage(_ message: VoiceMessage) async throws {
        guard let id = message.id else { return }

        // Delete from Storage
        let storageRef = storage.reference(forURL: message.audioURL)
        try await storageRef.delete()

        // Delete from Firestore
        try await db.collection("voiceMessages").document(id).delete()
    }

    // MARK: - Photos
    func uploadPhoto(imageData: Data, caption: String, uploadedBy: String) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("photos/\(fileName)")

        let _ = try await storageRef.putDataAsync(imageData)
        let downloadURL = try await storageRef.downloadURL()

        let photo = Photo(
            imageURL: downloadURL.absoluteString,
            caption: caption,
            uploadedBy: uploadedBy,
            createdAt: Date()
        )

        try db.collection("photos").addDocument(from: photo)
        return downloadURL.absoluteString
    }

    func getPhotos() -> AsyncThrowingStream<[Photo], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("photos")
                .order(by: "createdAt", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    let photos = documents.compactMap { doc -> Photo? in
                        try? doc.data(as: Photo.self)
                    }

                    continuation.yield(photos)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func deletePhoto(_ photo: Photo) async throws {
        guard let id = photo.id else { return }

        // Delete from Storage
        let storageRef = storage.reference(forURL: photo.imageURL)
        try await storageRef.delete()

        // Delete from Firestore
        try await db.collection("photos").document(id).delete()
    }

    // MARK: - Calendar Events
    func addCalendarEvent(_ event: CalendarEvent) async throws {
        try db.collection("calendarEvents").addDocument(from: event)
    }

    func getCalendarEvents() -> AsyncThrowingStream<[CalendarEvent], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("calendarEvents")
                .order(by: "date")
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    let events = documents.compactMap { doc -> CalendarEvent? in
                        try? doc.data(as: CalendarEvent.self)
                    }

                    continuation.yield(events)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func updateCalendarEvent(_ event: CalendarEvent) async throws {
        guard let id = event.id else { return }
        try db.collection("calendarEvents").document(id).setData(from: event)
    }

    func deleteCalendarEvent(_ event: CalendarEvent) async throws {
        guard let id = event.id else { return }
        try await db.collection("calendarEvents").document(id).delete()
    }
}
