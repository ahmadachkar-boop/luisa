import Foundation
import Network
import Combine

// MARK: - Network Status
/// Detailed network status information
struct NetworkStatus: Equatable {
    let isConnected: Bool
    let connectionType: ConnectionType
    let isExpensive: Bool       // Cellular or hotspot
    let isConstrained: Bool     // Low Data Mode enabled

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unknown = "Unknown"
        case none = "No Connection"
    }

    static let disconnected = NetworkStatus(
        isConnected: false,
        connectionType: .none,
        isExpensive: false,
        isConstrained: false
    )
}

// MARK: - Network Error
enum NetworkError: LocalizedError {
    case noConnection
    case poorConnection
    case timeout

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .poorConnection:
            return "Poor internet connection. Please try again later."
        case .timeout:
            return "Request timed out. Please check your connection."
        }
    }
}

// MARK: - Offline Manager
// Handles caching events/photos for offline viewing and queuing uploads

class OfflineManager: ObservableObject {
    static let shared = OfflineManager()

    @Published var isOnline: Bool = true
    @Published var pendingOperationsCount: Int = 0
    @Published private(set) var networkStatus: NetworkStatus = .disconnected

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ourapp.networkmonitor")

    private let cacheDirectory: URL
    private let pendingOperationsKey = "pendingOperations"

    private init() {
        // Setup cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("OfflineCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Start network monitoring
        startNetworkMonitoring()

        // Load pending operations count
        loadPendingOperationsCount()
    }

    // MARK: - Network Monitoring
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                // Update detailed network status
                self?.networkStatus = self?.parseNetworkPath(path) ?? .disconnected

                // If we just came online, process pending operations
                if wasOffline && path.status == .satisfied {
                    self?.processPendingOperations()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Parse NWPath to extract detailed network information
    private func parseNetworkPath(_ path: NWPath) -> NetworkStatus {
        let isConnected = path.status == .satisfied

        // Determine connection type
        let connectionType: NetworkStatus.ConnectionType
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else if isConnected {
            connectionType = .unknown
        } else {
            connectionType = .none
        }

        return NetworkStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    // MARK: - Reachability Check

    /// Check if network is available before performing an operation
    /// Returns nil if connected, or NetworkError if not
    func checkReachability() -> NetworkError? {
        if !isOnline {
            return .noConnection
        }
        return nil
    }

    /// Perform an operation only if online, otherwise queue it for later
    /// - Parameters:
    ///   - operation: The async operation to perform
    ///   - offlineHandler: Optional handler called when offline
    /// - Returns: Result of the operation or nil if queued
    func performWhenOnline<T>(
        operation: @escaping () async throws -> T,
        offlineHandler: (() -> Void)? = nil
    ) async throws -> T? {
        if isOnline {
            return try await operation()
        } else {
            offlineHandler?()
            return nil
        }
    }

    // MARK: - Event Caching
    func cacheEvents(_ events: [CalendarEvent]) {
        let cacheURL = cacheDirectory.appendingPathComponent("events.json")

        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: cacheURL)
        } catch {
            print("OfflineManager: Failed to cache events - \(error)")
        }
    }

    func loadCachedEvents() -> [CalendarEvent]? {
        let cacheURL = cacheDirectory.appendingPathComponent("events.json")

        guard let data = try? Data(contentsOf: cacheURL),
              let events = try? JSONDecoder().decode([CalendarEvent].self, from: data) else {
            return nil
        }

        return events
    }

    // MARK: - Photo Metadata Caching
    func cachePhotoMetadata(_ photos: [Photo]) {
        let cacheURL = cacheDirectory.appendingPathComponent("photos.json")

        do {
            let data = try JSONEncoder().encode(photos)
            try data.write(to: cacheURL)
        } catch {
            print("OfflineManager: Failed to cache photo metadata - \(error)")
        }
    }

    func loadCachedPhotoMetadata() -> [Photo]? {
        let cacheURL = cacheDirectory.appendingPathComponent("photos.json")

        guard let data = try? Data(contentsOf: cacheURL),
              let photos = try? JSONDecoder().decode([Photo].self, from: data) else {
            return nil
        }

        return photos
    }

    // MARK: - Pending Operations Queue
    enum PendingOperationType: String, Codable {
        case uploadPhoto
        case deletePhoto
        case addEvent
        case updateEvent
        case deleteEvent
        case toggleFavorite
        case moveToFolder
    }

    struct PendingOperation: Codable, Identifiable {
        let id: String
        let type: PendingOperationType
        let data: Data // JSON encoded operation data
        let createdAt: Date
        var retryCount: Int
        var lastRetryAt: Date?

        // Maximum retries before operation is discarded
        static let maxRetries = 5
        // Maximum age before operation is considered stale (7 days)
        static let maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

        init(type: PendingOperationType, data: Data) {
            self.id = UUID().uuidString
            self.type = type
            self.data = data
            self.createdAt = Date()
            self.retryCount = 0
            self.lastRetryAt = nil
        }

        // Calculate exponential backoff delay in seconds
        func backoffDelay() -> TimeInterval {
            // 2^retryCount seconds: 1s, 2s, 4s, 8s, 16s
            return pow(2.0, Double(retryCount))
        }

        // Check if enough time has passed for next retry
        func canRetryNow() -> Bool {
            guard let lastRetry = lastRetryAt else { return true }
            return Date().timeIntervalSince(lastRetry) >= backoffDelay()
        }

        // Check if operation is too old and should be discarded
        func isStale() -> Bool {
            return Date().timeIntervalSince(createdAt) > PendingOperation.maxAgeSeconds
        }

        // Check if operation has exceeded max retries
        func hasExceededMaxRetries() -> Bool {
            return retryCount >= PendingOperation.maxRetries
        }
    }

    func queueOperation(_ operation: PendingOperation) {
        var operations = loadPendingOperations()
        operations.append(operation)
        savePendingOperations(operations)

        DispatchQueue.main.async {
            self.pendingOperationsCount = operations.count
        }
    }

    private func loadPendingOperations() -> [PendingOperation] {
        let cacheURL = cacheDirectory.appendingPathComponent("pendingOperations.json")

        guard let data = try? Data(contentsOf: cacheURL),
              let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            return []
        }

        return operations
    }

    private func savePendingOperations(_ operations: [PendingOperation]) {
        let cacheURL = cacheDirectory.appendingPathComponent("pendingOperations.json")

        do {
            let data = try JSONEncoder().encode(operations)
            try data.write(to: cacheURL)
        } catch {
            print("OfflineManager: Failed to save pending operations - \(error)")
        }
    }

    private func loadPendingOperationsCount() {
        pendingOperationsCount = loadPendingOperations().count
    }

    private func removePendingOperation(_ id: String) {
        var operations = loadPendingOperations()
        operations.removeAll { $0.id == id }
        savePendingOperations(operations)

        DispatchQueue.main.async {
            self.pendingOperationsCount = operations.count
        }
    }

    // MARK: - Process Pending Operations
    func processPendingOperations() {
        guard isOnline else { return }

        var operations = loadPendingOperations()
        guard !operations.isEmpty else { return }

        // First, clean up stale and max-retried operations
        let (validOperations, discardedCount) = cleanupOperations(operations)
        if discardedCount > 0 {
            print("OfflineManager: Discarded \(discardedCount) stale/failed operations")
            operations = validOperations
            savePendingOperations(operations)
            DispatchQueue.main.async {
                self.pendingOperationsCount = operations.count
            }
        }

        Task {
            var updatedOperations = operations

            for (index, operation) in operations.enumerated() {
                // Check if operation can be retried (respecting backoff)
                guard operation.canRetryNow() else {
                    print("OfflineManager: Skipping operation \(operation.id) - backoff not elapsed")
                    continue
                }

                do {
                    try await processOperation(operation)
                    // Success - remove from queue
                    removePendingOperation(operation.id)
                    print("OfflineManager: Successfully processed operation \(operation.id)")
                } catch {
                    print("OfflineManager: Failed to process operation \(operation.id) (attempt \(operation.retryCount + 1)) - \(error)")

                    // Update retry count and last retry time
                    var failedOp = operation
                    failedOp.retryCount += 1
                    failedOp.lastRetryAt = Date()

                    // Check if we've exceeded max retries
                    if failedOp.hasExceededMaxRetries() {
                        print("OfflineManager: Operation \(operation.id) exceeded max retries, discarding")
                        removePendingOperation(operation.id)
                    } else {
                        // Update the operation in the queue
                        updatedOperations[index] = failedOp
                        savePendingOperations(updatedOperations)
                    }
                }
            }
        }
    }

    // Clean up operations that are too old or have exceeded max retries
    private func cleanupOperations(_ operations: [PendingOperation]) -> (valid: [PendingOperation], discardedCount: Int) {
        var valid: [PendingOperation] = []
        var discarded = 0

        for op in operations {
            if op.isStale() {
                print("OfflineManager: Discarding stale operation \(op.id) (age: \(Date().timeIntervalSince(op.createdAt) / 86400) days)")
                discarded += 1
            } else if op.hasExceededMaxRetries() {
                print("OfflineManager: Discarding operation \(op.id) (exceeded \(PendingOperation.maxRetries) retries)")
                discarded += 1
            } else {
                valid.append(op)
            }
        }

        return (valid, discarded)
    }

    private func processOperation(_ operation: PendingOperation) async throws {
        let firebaseManager = FirebaseManager.shared

        switch operation.type {
        case .uploadPhoto:
            // Photo upload data: [imageFilePath: String, capturedAt: Date?, eventId: String?, folderId: String?]
            guard let uploadData = try? JSONDecoder().decode(PhotoUploadData.self, from: operation.data) else {
                throw OfflineError.invalidData
            }

            // Load image data from temporary file
            let tempFileURL = cacheDirectory.appendingPathComponent(uploadData.imageFilePath)
            guard let imageData = try? Data(contentsOf: tempFileURL) else {
                print("OfflineManager: Could not load image from temp file - \(uploadData.imageFilePath)")
                throw OfflineError.invalidData
            }

            _ = try await firebaseManager.uploadPhoto(
                imageData: imageData,
                caption: "",
                uploadedBy: UserIdentityManager.shared.currentUserName,
                capturedAt: uploadData.capturedAt,
                eventId: uploadData.eventId,
                folderId: uploadData.folderId
            )

            // Clean up temporary file after successful upload
            try? FileManager.default.removeItem(at: tempFileURL)

        case .deletePhoto:
            guard let photo = try? JSONDecoder().decode(Photo.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.deletePhoto(photo)

        case .addEvent:
            guard let event = try? JSONDecoder().decode(CalendarEvent.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.addCalendarEvent(event)

        case .updateEvent:
            guard let event = try? JSONDecoder().decode(CalendarEvent.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.updateEvent(event)

        case .deleteEvent:
            guard let event = try? JSONDecoder().decode(CalendarEvent.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.deleteCalendarEvent(event)

        case .toggleFavorite:
            guard let favoriteData = try? JSONDecoder().decode(FavoriteToggleData.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.togglePhotoFavorite(favoriteData.photoId, isFavorite: favoriteData.isFavorite)

        case .moveToFolder:
            guard let moveData = try? JSONDecoder().decode(MoveToFolderData.self, from: operation.data) else {
                throw OfflineError.invalidData
            }
            try await firebaseManager.updatePhotoFolder(moveData.photoId, folderId: moveData.folderId)
        }
    }

    // MARK: - Helper Data Structures
    struct PhotoUploadData: Codable {
        let imageFilePath: String // Path to temporary file instead of raw data
        let capturedAt: Date?
        let eventId: String?
        let folderId: String?
    }

    struct FavoriteToggleData: Codable {
        let photoId: String
        let isFavorite: Bool
    }

    struct MoveToFolderData: Codable {
        let photoId: String
        let folderId: String?
    }

    enum OfflineError: Error {
        case invalidData
        case networkUnavailable
    }

    // MARK: - Convenience Methods
    func queuePhotoUpload(imageData: Data, capturedAt: Date?, eventId: String?, folderId: String?) {
        // Save image data to a temporary file to avoid memory-intensive JSON encoding
        let tempFileName = "pending_upload_\(UUID().uuidString).jpg"
        let tempFileURL = cacheDirectory.appendingPathComponent(tempFileName)

        do {
            try imageData.write(to: tempFileURL)
        } catch {
            print("OfflineManager: Failed to save image for offline upload - \(error)")
            return
        }

        let uploadData = PhotoUploadData(
            imageFilePath: tempFileName,
            capturedAt: capturedAt,
            eventId: eventId,
            folderId: folderId
        )

        guard let data = try? JSONEncoder().encode(uploadData) else { return }
        let operation = PendingOperation(type: .uploadPhoto, data: data)
        queueOperation(operation)
    }

    func queueEventAdd(_ event: CalendarEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let operation = PendingOperation(type: .addEvent, data: data)
        queueOperation(operation)
    }

    func queueEventUpdate(_ event: CalendarEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let operation = PendingOperation(type: .updateEvent, data: data)
        queueOperation(operation)
    }

    func queueEventDelete(_ event: CalendarEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let operation = PendingOperation(type: .deleteEvent, data: data)
        queueOperation(operation)
    }

    func queueFavoriteToggle(photoId: String, isFavorite: Bool) {
        let toggleData = FavoriteToggleData(photoId: photoId, isFavorite: isFavorite)
        guard let data = try? JSONEncoder().encode(toggleData) else { return }
        let operation = PendingOperation(type: .toggleFavorite, data: data)
        queueOperation(operation)
    }

    func queueMoveToFolder(photoId: String, folderId: String?) {
        let moveData = MoveToFolderData(photoId: photoId, folderId: folderId)
        guard let data = try? JSONEncoder().encode(moveData) else { return }
        let operation = PendingOperation(type: .moveToFolder, data: data)
        queueOperation(operation)
    }

    // MARK: - Clear Cache
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        pendingOperationsCount = 0
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - View for Offline Indicator
import SwiftUI

struct OfflineIndicatorView: View {
    @ObservedObject var offlineManager = OfflineManager.shared

    var body: some View {
        if !offlineManager.isOnline || offlineManager.pendingOperationsCount > 0 {
            HStack(spacing: 8) {
                if !offlineManager.isOnline {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                if offlineManager.pendingOperationsCount > 0 {
                    if !offlineManager.isOnline {
                        Text("•")
                            .font(.caption)
                    }
                    Text("\(offlineManager.pendingOperationsCount) pending")
                        .font(.caption)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(offlineManager.isOnline ? Color.orange : Color.gray)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
