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

    func fetchAllEvents() async throws -> [CalendarEvent] {
        let snapshot = try await db.collection("calendarEvents")
            .order(by: "date")
            .getDocuments()

        return snapshot.documents.compactMap { doc -> CalendarEvent? in
            try? doc.data(as: CalendarEvent.self)
        }
    }

    func updateEvent(_ event: CalendarEvent) async throws {
        guard let id = event.id else {
            print("🔴 [FIREBASE ERROR] Event has no ID!")
            return
        }
        try db.collection("calendarEvents").document(id).setData(from: event)
    }

    func updateCalendarEvent(_ event: CalendarEvent) async throws {
        print("🔵 [FIREBASE] updateCalendarEvent called")
        guard let id = event.id else {
            print("🔴 [FIREBASE ERROR] Event has no ID!")
            return
        }
        print("🔵 [FIREBASE] Updating event \(id) with \(event.photoURLs.count) photos")
        try db.collection("calendarEvents").document(id).setData(from: event)
        print("🟢 [FIREBASE SUCCESS] Event \(id) updated successfully")
    }

    func deleteCalendarEvent(_ event: CalendarEvent) async throws {
        guard let id = event.id else { return }

        // Delete from Google Calendar if synced
        if let googleCalendarId = event.googleCalendarId {
            do {
                print("🔵 [GOOGLE SYNC] Deleting event from Google Calendar: \(googleCalendarId)")
                try await GoogleCalendarManager.shared.deleteEventFromGoogle(googleCalendarId)
                print("✅ [GOOGLE SYNC] Event deleted from Google Calendar")
            } catch {
                print("⚠️ [GOOGLE SYNC] Failed to delete from Google Calendar: \(error.localizedDescription)")
                // Continue with local deletion even if Google deletion fails
            }
        }

        // Delete event photos from storage
        for photoURL in event.photoURLs {
            do {
                let storageRef = storage.reference(forURL: photoURL)
                try await storageRef.delete()
            } catch {
                print("Error deleting event photo: \(error)")
            }
        }

        try await db.collection("calendarEvents").document(id).delete()
    }

    func uploadEventPhoto(imageData: Data) async throws -> String {
        print("🔵 [FIREBASE STORAGE] uploadEventPhoto called with \(imageData.count) bytes")
        let fileName = "\(UUID().uuidString).jpg"
        print("🔵 [FIREBASE STORAGE] Generated filename: \(fileName)")
        let storageRef = storage.reference().child("event_photos/\(fileName)")
        print("🔵 [FIREBASE STORAGE] Storage path: event_photos/\(fileName)")

        print("🔵 [FIREBASE STORAGE] Starting upload...")
        let _ = try await storageRef.putDataAsync(imageData)
        print("🟢 [FIREBASE STORAGE] Upload complete, fetching download URL...")

        let downloadURL = try await storageRef.downloadURL()
        print("🟢 [FIREBASE STORAGE] Download URL obtained: \(downloadURL.absoluteString)")

        return downloadURL.absoluteString
    }

    // MARK: - Wish List
    func addWishListItem(_ item: WishListItem) async throws {
        try db.collection("wishList").addDocument(from: item)
    }

    func getWishListItems() -> AsyncThrowingStream<[WishListItem], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("wishList")
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

                    let items = documents.compactMap { doc -> WishListItem? in
                        try? doc.data(as: WishListItem.self)
                    }

                    continuation.yield(items)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func updateWishListItem(_ item: WishListItem) async throws {
        guard let id = item.id else { return }
        try db.collection("wishList").document(id).setData(from: item)
    }

    func deleteWishListItem(_ item: WishListItem) async throws {
        guard let id = item.id else { return }
        try await db.collection("wishList").document(id).delete()
    }
}
