import Foundation
import BackgroundTasks
import UIKit
import UserNotifications

// MARK: - Background Task Identifiers
/// Centralized identifiers for all background tasks in the app
enum BackgroundTaskIdentifier: String, CaseIterable {
    /// Process pending photo and voice memo uploads
    case pendingUploads = "com.ourapp.pending-uploads"
    /// Sync with Google Calendar
    case googleCalendarSync = "com.ourapp.google-calendar-sync"
    /// Refresh app data (events, photos metadata, wishlist)
    case dataRefresh = "com.ourapp.data-refresh"
    /// Clean up disk cache and orphaned data
    case cacheCleanup = "com.ourapp.cache-cleanup"

    var isProcessingTask: Bool {
        switch self {
        case .pendingUploads, .cacheCleanup:
            return true
        case .googleCalendarSync, .dataRefresh:
            return false
        }
    }
}

// MARK: - Background Task Result
enum BackgroundTaskResult {
    case success(itemsProcessed: Int)
    case partialSuccess(processed: Int, failed: Int)
    case noWork
    case failed(Error)

    var succeeded: Bool {
        switch self {
        case .success, .partialSuccess, .noWork:
            return true
        case .failed:
            return false
        }
    }
}

// MARK: - Background Task Manager
/// Centralized manager for all background processing in the app using BGTaskScheduler.
/// Handles photo uploads, voice memo uploads, Google Calendar sync, data refresh, and cache cleanup.
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    // MARK: - Properties

    /// Track if background tasks have been registered
    private var isRegistered = false

    /// Minimum time between background refresh attempts (15 minutes)
    private let minimumBackgroundFetchInterval: TimeInterval = 15 * 60

    /// Track last successful task completions
    private var lastTaskCompletions: [BackgroundTaskIdentifier: Date] = [:]

    /// Active background task references for cancellation
    private var activeBackgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]

    /// Serial queue for thread-safe operations
    private let taskQueue = DispatchQueue(label: "com.ourapp.backgroundtask.queue")

    private init() {
        loadLastCompletionDates()
    }

    // MARK: - Registration

    /// Register all background task handlers with the system.
    /// MUST be called from application(_:didFinishLaunchingWithOptions:) before returning.
    func registerBackgroundTasks() {
        guard !isRegistered else {
            print("⚠️ [BACKGROUND] Tasks already registered")
            return
        }

        print("🔵 [BACKGROUND] Registering background task handlers...")

        // Register processing tasks (longer running, needs power)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.pendingUploads.rawValue,
            using: nil
        ) { [weak self] task in
            self?.handlePendingUploadsTask(task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.cacheCleanup.rawValue,
            using: nil
        ) { [weak self] task in
            self?.handleCacheCleanupTask(task as! BGProcessingTask)
        }

        // Register app refresh tasks (shorter, more frequent)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.googleCalendarSync.rawValue,
            using: nil
        ) { [weak self] task in
            self?.handleGoogleCalendarSyncTask(task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.dataRefresh.rawValue,
            using: nil
        ) { [weak self] task in
            self?.handleDataRefreshTask(task as! BGAppRefreshTask)
        }

        isRegistered = true
        print("🟢 [BACKGROUND] All background task handlers registered")
    }

    // MARK: - Task Scheduling

    /// Schedule all background tasks. Called when app enters background.
    func scheduleAllBackgroundTasks() {
        scheduleTask(.pendingUploads)
        scheduleTask(.googleCalendarSync)
        scheduleTask(.dataRefresh)
        scheduleTask(.cacheCleanup)
    }

    /// Schedule a specific background task
    func scheduleTask(_ taskId: BackgroundTaskIdentifier) {
        taskQueue.async { [weak self] in
            self?.scheduleTaskInternal(taskId)
        }
    }

    private func scheduleTaskInternal(_ taskId: BackgroundTaskIdentifier) {
        // Cancel any existing scheduled task of this type
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId.rawValue)

        if taskId.isProcessingTask {
            // Processing tasks for heavy work
            let request = BGProcessingTaskRequest(identifier: taskId.rawValue)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false // Don't require charging

            // Schedule based on task type
            switch taskId {
            case .pendingUploads:
                // Process uploads as soon as possible
                request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 minute

            case .cacheCleanup:
                // Cache cleanup can wait until overnight
                request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // 6 hours
                request.requiresExternalPower = true // Prefer when charging

            default:
                request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
            }

            do {
                try BGTaskScheduler.shared.submit(request)
                print("🟢 [BACKGROUND] Scheduled processing task: \(taskId.rawValue)")
            } catch {
                print("🔴 [BACKGROUND] Failed to schedule \(taskId.rawValue): \(error.localizedDescription)")
            }

        } else {
            // App refresh tasks for quick sync
            let request = BGAppRefreshTaskRequest(identifier: taskId.rawValue)

            switch taskId {
            case .googleCalendarSync:
                // Sync calendar every 30 minutes minimum
                request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)

            case .dataRefresh:
                // Refresh data every 15 minutes
                request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

            default:
                request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            }

            do {
                try BGTaskScheduler.shared.submit(request)
                print("🟢 [BACKGROUND] Scheduled refresh task: \(taskId.rawValue)")
            } catch {
                print("🔴 [BACKGROUND] Failed to schedule \(taskId.rawValue): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Task Handlers

    /// Handle pending uploads (photos, voice memos) in background
    private func handlePendingUploadsTask(_ task: BGProcessingTask) {
        print("🔵 [BACKGROUND] Starting pending uploads task")

        // Schedule the next occurrence
        scheduleTask(.pendingUploads)

        // Create a task to process uploads
        let uploadTask = Task {
            await processPendingUploads()
        }

        // Handle expiration
        task.expirationHandler = {
            print("⚠️ [BACKGROUND] Pending uploads task expired")
            uploadTask.cancel()
        }

        // Wait for completion
        Task {
            let result = await processPendingUploads()

            await MainActor.run {
                task.setTaskCompleted(success: result.succeeded)
                self.recordTaskCompletion(.pendingUploads)
                print("🟢 [BACKGROUND] Pending uploads task completed: \(result)")
            }
        }
    }

    /// Handle Google Calendar sync in background
    private func handleGoogleCalendarSyncTask(_ task: BGAppRefreshTask) {
        print("🔵 [BACKGROUND] Starting Google Calendar sync task")

        // Schedule the next occurrence
        scheduleTask(.googleCalendarSync)

        let syncTask = Task { @MainActor in
            await performGoogleCalendarSync()
        }

        task.expirationHandler = {
            print("⚠️ [BACKGROUND] Google Calendar sync task expired")
            syncTask.cancel()
        }

        Task {
            let result = await performGoogleCalendarSync()

            await MainActor.run {
                task.setTaskCompleted(success: result.succeeded)
                self.recordTaskCompletion(.googleCalendarSync)
                print("🟢 [BACKGROUND] Google Calendar sync task completed: \(result)")
            }
        }
    }

    /// Handle data refresh in background
    private func handleDataRefreshTask(_ task: BGAppRefreshTask) {
        print("🔵 [BACKGROUND] Starting data refresh task")

        // Schedule the next occurrence
        scheduleTask(.dataRefresh)

        let refreshTask = Task {
            await performDataRefresh()
        }

        task.expirationHandler = {
            print("⚠️ [BACKGROUND] Data refresh task expired")
            refreshTask.cancel()
        }

        Task {
            let result = await performDataRefresh()

            await MainActor.run {
                task.setTaskCompleted(success: result.succeeded)
                self.recordTaskCompletion(.dataRefresh)
                print("🟢 [BACKGROUND] Data refresh task completed: \(result)")
            }
        }
    }

    /// Handle cache cleanup in background
    private func handleCacheCleanupTask(_ task: BGProcessingTask) {
        print("🔵 [BACKGROUND] Starting cache cleanup task")

        // Schedule the next occurrence (infrequent - once per day)
        scheduleTask(.cacheCleanup)

        let cleanupTask = Task {
            await performCacheCleanup()
        }

        task.expirationHandler = {
            print("⚠️ [BACKGROUND] Cache cleanup task expired")
            cleanupTask.cancel()
        }

        Task {
            let result = await performCacheCleanup()

            await MainActor.run {
                task.setTaskCompleted(success: result.succeeded)
                self.recordTaskCompletion(.cacheCleanup)
                print("🟢 [BACKGROUND] Cache cleanup task completed: \(result)")
            }
        }
    }

    // MARK: - Task Implementations

    /// Process all pending uploads from OfflineManager
    private func processPendingUploads() async -> BackgroundTaskResult {
        let offlineManager = OfflineManager.shared

        // Check if we're online
        guard offlineManager.isOnline else {
            print("⚠️ [BACKGROUND] Skipping uploads - device is offline")
            return .noWork
        }

        let pendingCount = offlineManager.pendingOperationsCount
        guard pendingCount > 0 else {
            print("📭 [BACKGROUND] No pending uploads to process")
            return .noWork
        }

        print("📤 [BACKGROUND] Processing \(pendingCount) pending operations...")

        // Process pending operations (this handles retries internally)
        offlineManager.processPendingOperations()

        // Wait a bit for operations to complete
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

        let remainingCount = offlineManager.pendingOperationsCount
        let processedCount = pendingCount - remainingCount

        if remainingCount > 0 {
            return .partialSuccess(processed: processedCount, failed: remainingCount)
        } else {
            return .success(itemsProcessed: processedCount)
        }
    }

    /// Perform Google Calendar sync
    @MainActor
    private func performGoogleCalendarSync() async -> BackgroundTaskResult {
        let calendarManager = GoogleCalendarManager.shared

        // Check if signed in and auto-sync enabled
        guard calendarManager.isSignedIn else {
            print("⚠️ [BACKGROUND] Skipping calendar sync - not signed in")
            return .noWork
        }

        guard calendarManager.autoSyncEnabled else {
            print("⚠️ [BACKGROUND] Skipping calendar sync - auto-sync disabled")
            return .noWork
        }

        // Check if we recently synced (avoid excessive syncing)
        if let lastSync = calendarManager.lastSyncDate,
           Date().timeIntervalSince(lastSync) < 10 * 60 { // Less than 10 minutes ago
            print("⏭️ [BACKGROUND] Skipping calendar sync - recently synced")
            return .noWork
        }

        do {
            print("🔄 [BACKGROUND] Syncing Google Calendar...")
            try await calendarManager.syncEvents()
            print("✅ [BACKGROUND] Google Calendar sync successful")
            return .success(itemsProcessed: 1)
        } catch {
            print("🔴 [BACKGROUND] Google Calendar sync failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    /// Refresh app data (events, photos, wishlist metadata)
    private func performDataRefresh() async -> BackgroundTaskResult {
        print("🔄 [BACKGROUND] Refreshing app data...")

        var itemsRefreshed = 0

        // 1. Cache events for offline access
        do {
            let events = try await FirebaseManager.shared.fetchAllEvents()
            OfflineManager.shared.cacheEvents(events)
            itemsRefreshed += events.count
            print("✅ [BACKGROUND] Cached \(events.count) events")
        } catch {
            print("⚠️ [BACKGROUND] Failed to cache events: \(error.localizedDescription)")
        }

        // 2. Sync widget data
        await MainActor.run {
            WidgetDataManager.shared.syncFromFirebase()
        }
        itemsRefreshed += 1

        // 3. Pre-warm image cache for recent photos (first 10)
        // This is done via the existing prefetch mechanism

        print("✅ [BACKGROUND] Data refresh completed, \(itemsRefreshed) items processed")
        return .success(itemsProcessed: itemsRefreshed)
    }

    /// Clean up disk cache and orphaned data
    private func performCacheCleanup() async -> BackgroundTaskResult {
        print("🧹 [BACKGROUND] Starting cache cleanup...")

        var itemsCleaned = 0

        // 1. Clean up image disk cache
        // ImageCache handles this internally, but we can trigger it
        await MainActor.run {
            // Trigger cache cleanup
            ImageCache.shared.prefetch(urls: []) // Trigger cleanup cycle
        }

        // 2. Clean up orphaned photos in Firebase (if online)
        if OfflineManager.shared.isOnline {
            do {
                let orphanedCount = try await FirebaseManager.shared.cleanupOrphanedPhotos()
                itemsCleaned += orphanedCount
                print("✅ [BACKGROUND] Cleaned up \(orphanedCount) orphaned photos")
            } catch {
                print("⚠️ [BACKGROUND] Failed to cleanup orphaned photos: \(error.localizedDescription)")
            }
        }

        // 3. Clean up temporary upload files (older than 7 days)
        let tempFilesRemoved = cleanupTemporaryFiles()
        itemsCleaned += tempFilesRemoved

        print("✅ [BACKGROUND] Cache cleanup completed, \(itemsCleaned) items cleaned")
        return .success(itemsProcessed: itemsCleaned)
    }

    /// Clean up old temporary files from the offline cache directory
    private func cleanupTemporaryFiles() -> Int {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let offlineCacheDir = cacheDir.appendingPathComponent("OfflineCache", isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(
            at: offlineCacheDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return 0
        }

        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        var removedCount = 0

        for file in files {
            // Only clean up pending upload files
            guard file.lastPathComponent.hasPrefix("pending_upload_") else { continue }

            if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = attributes.creationDate,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: file)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            print("🗑️ [BACKGROUND] Removed \(removedCount) old temporary files")
        }

        return removedCount
    }

    // MARK: - Foreground Background Task Support

    /// Begin a background task for foreground operations that might take time.
    /// Use this when starting uploads or syncs while the app is in foreground.
    func beginForegroundBackgroundTask(name: String, expirationHandler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            print("⚠️ [BACKGROUND] Foreground task '\(name)' expired")
            expirationHandler?()

            // Clean up
            if let id = self?.activeBackgroundTasks[name] {
                UIApplication.shared.endBackgroundTask(id)
                self?.activeBackgroundTasks.removeValue(forKey: name)
            }
        }

        if taskId != .invalid {
            activeBackgroundTasks[name] = taskId
            print("🔵 [BACKGROUND] Started foreground background task: \(name)")
        }

        return taskId
    }

    /// End a foreground background task
    func endForegroundBackgroundTask(name: String) {
        if let taskId = activeBackgroundTasks[name] {
            UIApplication.shared.endBackgroundTask(taskId)
            activeBackgroundTasks.removeValue(forKey: name)
            print("🟢 [BACKGROUND] Ended foreground background task: \(name)")
        }
    }

    /// End a foreground background task by ID
    func endForegroundBackgroundTask(_ taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)

        // Remove from tracking
        activeBackgroundTasks = activeBackgroundTasks.filter { $0.value != taskId }
    }

    // MARK: - Persistence

    private func loadLastCompletionDates() {
        let defaults = UserDefaults.standard
        for taskId in BackgroundTaskIdentifier.allCases {
            if let date = defaults.object(forKey: "bg_task_\(taskId.rawValue)") as? Date {
                lastTaskCompletions[taskId] = date
            }
        }
    }

    private func recordTaskCompletion(_ taskId: BackgroundTaskIdentifier) {
        let now = Date()
        lastTaskCompletions[taskId] = now
        UserDefaults.standard.set(now, forKey: "bg_task_\(taskId.rawValue)")
    }

    /// Get the last completion date for a task
    func lastCompletion(for taskId: BackgroundTaskIdentifier) -> Date? {
        return lastTaskCompletions[taskId]
    }

    // MARK: - Debug Helpers

    /// Force trigger a background task (for testing)
    func debugTriggerTask(_ taskId: BackgroundTaskIdentifier) {
        #if DEBUG
        print("🧪 [DEBUG] Manually triggering task: \(taskId.rawValue)")

        Task {
            switch taskId {
            case .pendingUploads:
                let result = await processPendingUploads()
                print("🧪 [DEBUG] Result: \(result)")

            case .googleCalendarSync:
                let result = await performGoogleCalendarSync()
                print("🧪 [DEBUG] Result: \(result)")

            case .dataRefresh:
                let result = await performDataRefresh()
                print("🧪 [DEBUG] Result: \(result)")

            case .cacheCleanup:
                let result = await performCacheCleanup()
                print("🧪 [DEBUG] Result: \(result)")
            }
        }
        #endif
    }

    /// Print debug info about scheduled tasks
    func debugPrintScheduledTasks() {
        #if DEBUG
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            print("🧪 [DEBUG] Pending background tasks:")
            for request in requests {
                print("  - \(request.identifier): earliest \(String(describing: request.earliestBeginDate))")
            }
        }
        #endif
    }
}

// MARK: - Background Processing Extensions for Existing Managers

extension OfflineManager {
    /// Process pending operations with background task protection
    func processPendingOperationsInBackground() {
        let taskId = BackgroundTaskManager.shared.beginForegroundBackgroundTask(
            name: "PendingOperations"
        ) { [weak self] in
            // Task expired - operations will resume next time
            print("⚠️ [OFFLINE] Background time expired during pending operations")
            self?.objectWillChange.send()
        }

        guard taskId != .invalid else {
            // Couldn't get background time, process anyway
            processPendingOperations()
            return
        }

        // Process with background protection
        processPendingOperations()

        // End task after a delay to allow async operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            BackgroundTaskManager.shared.endForegroundBackgroundTask(taskId)
        }
    }
}

extension UploadProgressManager {
    /// Create a batch with background task protection
    func createBackgroundProtectedBatch(count: Int, type: UploadTask.UploadType, eventId: String? = nil) -> (batchId: String, taskId: UIBackgroundTaskIdentifier) {
        let taskName = "Upload_\(type.rawValue)_\(UUID().uuidString.prefix(8))"

        let backgroundTaskId = BackgroundTaskManager.shared.beginForegroundBackgroundTask(
            name: taskName
        ) {
            print("⚠️ [UPLOAD] Background time expired for \(taskName)")
        }

        let batchId = createBatch(count: count, type: type, eventId: eventId)

        return (batchId, backgroundTaskId)
    }

    /// Complete a batch and end its background task
    func completeBackgroundProtectedBatch(_ backgroundTaskId: UIBackgroundTaskIdentifier) {
        BackgroundTaskManager.shared.endForegroundBackgroundTask(backgroundTaskId)
    }
}
