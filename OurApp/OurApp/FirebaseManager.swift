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

    // MARK: - Voice Message Favorites
    func toggleVoiceMemoFavorite(_ memoId: String, isFavorite: Bool) async throws {
        try await db.collection("voiceMessages").document(memoId).updateData([
            "isFavorite": isFavorite
        ])
    }

    func batchToggleVoiceMemoFavorites(_ memoIds: [String], isFavorite: Bool, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        let batch = db.batch()
        let total = memoIds.count

        for (index, memoId) in memoIds.enumerated() {
            let docRef = db.collection("voiceMessages").document(memoId)
            batch.updateData(["isFavorite": isFavorite], forDocument: docRef)

            await MainActor.run {
                progressHandler?(index + 1, total)
            }
        }

        try await batch.commit()
    }

    // MARK: - Voice Memo Folders
    func createVoiceMemoFolder(name: String, forUser: String) async throws -> String {
        let folder = VoiceMemoFolder(
            name: name,
            createdAt: Date(),
            forUser: forUser
        )

        let docRef = try db.collection("voiceMemoFolders").addDocument(from: folder)
        return docRef.documentID
    }

    func getVoiceMemoFolders() -> AsyncThrowingStream<[VoiceMemoFolder], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("voiceMemoFolders")
                .order(by: "createdAt")
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    let folders = documents.compactMap { doc -> VoiceMemoFolder? in
                        try? doc.data(as: VoiceMemoFolder.self)
                    }

                    continuation.yield(folders)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func deleteVoiceMemoFolder(_ folder: VoiceMemoFolder) async throws {
        guard let id = folder.id else { return }

        // Remove folder reference from all voice memos in this folder
        let memosSnapshot = try await db.collection("voiceMessages")
            .whereField("folderId", isEqualTo: id)
            .getDocuments()

        for doc in memosSnapshot.documents {
            try await db.collection("voiceMessages").document(doc.documentID).updateData([
                "folderId": FieldValue.delete()
            ])
        }

        // Delete the folder
        try await db.collection("voiceMemoFolders").document(id).delete()
    }

    func updateVoiceMemoFolder(_ memoId: String, folderId: String?) async throws {
        if let folderId = folderId {
            try await db.collection("voiceMessages").document(memoId).updateData([
                "folderId": folderId
            ])
        } else {
            try await db.collection("voiceMessages").document(memoId).updateData([
                "folderId": FieldValue.delete()
            ])
        }
    }

    func batchUpdateVoiceMemoFolders(_ memoIds: [String], folderId: String?, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        let batch = db.batch()
        let total = memoIds.count

        for (index, memoId) in memoIds.enumerated() {
            let docRef = db.collection("voiceMessages").document(memoId)
            if let folderId = folderId {
                batch.updateData(["folderId": folderId], forDocument: docRef)
            } else {
                batch.updateData(["folderId": FieldValue.delete()], forDocument: docRef)
            }

            await MainActor.run {
                progressHandler?(index + 1, total)
            }
        }

        try await batch.commit()
    }

    // MARK: - Photos
    func uploadPhoto(imageData: Data, caption: String = "", uploadedBy: String = "You", capturedAt: Date? = nil, eventId: String? = nil, folderId: String? = nil) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("photos/\(fileName)")

        let _ = try await storageRef.putDataAsync(imageData)
        let downloadURL = try await storageRef.downloadURL()

        let photo = Photo(
            imageURL: downloadURL.absoluteString,
            caption: caption,
            uploadedBy: uploadedBy,
            createdAt: Date(),
            capturedAt: capturedAt,
            eventId: eventId,
            folderId: folderId
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

    func deletePhotoByURL(_ photoURL: String) async throws {
        // Query for the photo document with this URL
        let photosSnapshot = try await db.collection("photos")
            .whereField("imageURL", isEqualTo: photoURL)
            .getDocuments()

        // Delete all matching photos (should be just one, but handle multiple just in case)
        for doc in photosSnapshot.documents {
            // Delete from Storage
            do {
                let storageRef = storage.reference(forURL: photoURL)
                try await storageRef.delete()
            } catch {
                print("Error deleting photo from storage: \(error)")
                // Continue with Firestore deletion even if Storage deletion fails
            }

            // Delete from Firestore
            try await db.collection("photos").document(doc.documentID).delete()
        }
    }

    func cleanupOrphanedPhotos() async throws -> Int {
        print("🧹 [CLEANUP] Starting orphaned photos cleanup...")
        var deletedCount = 0

        // Get all photos from Firestore
        let photosSnapshot = try await db.collection("photos").getDocuments()

        for doc in photosSnapshot.documents {
            guard let photo = try? doc.data(as: Photo.self) else { continue }

            // Try to get metadata for the photo in Storage
            do {
                let storageRef = storage.reference(forURL: photo.imageURL)
                _ = try await storageRef.getMetadata()
                // Photo exists in Storage, skip it
            } catch {
                // Photo doesn't exist in Storage (404 or other error)
                // Delete the orphaned Firestore document
                print("🗑️ [CLEANUP] Deleting orphaned photo document: \(photo.imageURL)")
                try? await db.collection("photos").document(doc.documentID).delete()
                deletedCount += 1
            }
        }

        print("🟢 [CLEANUP] Cleanup complete. Deleted \(deletedCount) orphaned photo documents")
        return deletedCount
    }

    // MARK: - Photo Folders
    func createFolder(name: String, type: PhotoFolder.FolderType, eventId: String? = nil, isSpecialEvent: Bool? = nil) async throws -> String {
        let folder = PhotoFolder(
            name: name,
            createdAt: Date(),
            type: type,
            eventId: eventId,
            isSpecialEvent: isSpecialEvent
        )

        let docRef = try db.collection("photoFolders").addDocument(from: folder)
        return docRef.documentID
    }

    func getFolders() -> AsyncThrowingStream<[PhotoFolder], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("photoFolders")
                .order(by: "createdAt")
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    let folders = documents.compactMap { doc -> PhotoFolder? in
                        try? doc.data(as: PhotoFolder.self)
                    }

                    continuation.yield(folders)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func deleteFolder(_ folder: PhotoFolder) async throws {
        guard let id = folder.id else { return }

        // Remove folder reference from all photos in this folder
        let photosSnapshot = try await db.collection("photos")
            .whereField("folderId", isEqualTo: id)
            .getDocuments()

        for doc in photosSnapshot.documents {
            try await db.collection("photos").document(doc.documentID).updateData([
                "folderId": FieldValue.delete()
            ])
        }

        // Delete the folder
        try await db.collection("photoFolders").document(id).delete()
    }

    func updatePhotoFolder(_ photoId: String, folderId: String?) async throws {
        if let folderId = folderId {
            try await db.collection("photos").document(photoId).updateData([
                "folderId": folderId
            ])
        } else {
            try await db.collection("photos").document(photoId).updateData([
                "folderId": FieldValue.delete()
            ])
        }
    }

    // MARK: - Photo Favorites
    func togglePhotoFavorite(_ photoId: String, isFavorite: Bool) async throws {
        try await db.collection("photos").document(photoId).updateData([
            "isFavorite": isFavorite
        ])
    }

    func updatePhoto(_ photo: Photo) async throws {
        guard let id = photo.id else { return }
        try db.collection("photos").document(id).setData(from: photo)
    }

    // MARK: - Batch Operations
    func batchUpdatePhotoFolders(_ photoIds: [String], folderId: String?, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        let batch = db.batch()
        let total = photoIds.count

        for (index, photoId) in photoIds.enumerated() {
            let docRef = db.collection("photos").document(photoId)
            if let folderId = folderId {
                batch.updateData(["folderId": folderId], forDocument: docRef)
            } else {
                batch.updateData(["folderId": FieldValue.delete()], forDocument: docRef)
            }

            // Report progress
            await MainActor.run {
                progressHandler?(index + 1, total)
            }
        }

        try await batch.commit()
    }

    func batchToggleFavorites(_ photoIds: [String], isFavorite: Bool, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        let batch = db.batch()
        let total = photoIds.count

        for (index, photoId) in photoIds.enumerated() {
            let docRef = db.collection("photos").document(photoId)
            batch.updateData(["isFavorite": isFavorite], forDocument: docRef)

            await MainActor.run {
                progressHandler?(index + 1, total)
            }
        }

        try await batch.commit()
    }

    func batchDeletePhotos(_ photos: [Photo], progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        let total = photos.count

        for (index, photo) in photos.enumerated() {
            guard let id = photo.id else { continue }

            // Delete from Storage
            do {
                let storageRef = storage.reference(forURL: photo.imageURL)
                try await storageRef.delete()
            } catch {
                print("Error deleting photo from storage: \(error)")
            }

            // Delete from Firestore
            try await db.collection("photos").document(id).delete()

            await MainActor.run {
                progressHandler?(index + 1, total)
            }
        }
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

        // Delete photo documents from Firestore collection that reference this event
        // This ensures the photos collection is cleaned up and cross-tab sync works correctly
        let photosSnapshot = try await db.collection("photos")
            .whereField("eventId", isEqualTo: id)
            .getDocuments()

        for doc in photosSnapshot.documents {
            do {
                // Also delete the photo from storage if it exists
                if let photo = try? doc.data(as: Photo.self) {
                    let storageRef = storage.reference(forURL: photo.imageURL)
                    try? await storageRef.delete()
                }
                // Delete the photo document from Firestore
                try await db.collection("photos").document(doc.documentID).delete()
            } catch {
                print("Error deleting photo document: \(error)")
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
