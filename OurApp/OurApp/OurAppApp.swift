import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import GoogleSignIn
import UserNotifications
import BackgroundTasks
import AVFoundation
import ImageIO

// MARK: - App Delegate for Push Notifications and Background Tasks
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure Firebase FIRST before anything else
        print("🔵 [APP INIT] Starting OurApp initialization")
        print("🔵 [APP INIT] Configuring Firebase...")
        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            print("🟢 [APP INIT] Firebase configured successfully")
            print("🟢 [APP INIT] Firebase app name: \(app.name)")
            if let bundleID = Bundle.main.bundleIdentifier {
                print("🟢 [APP INIT] Bundle ID: \(bundleID)")
            }

            // Sync events to widget after Firebase is configured
            print("🔵 [APP INIT] Syncing events to widget...")
            WidgetDataManager.shared.syncFromFirebase()

            // Share Firebase config with Share Extension for direct uploads
            shareFirebaseConfigWithExtension()
        } else {
            print("🔴 [APP INIT ERROR] Firebase app is nil after configuration!")
        }

        // Register background tasks BEFORE returning from this method
        // This is required by iOS - tasks must be registered at launch
        print("🔵 [APP INIT] Registering background tasks...")
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // Setup notifications after Firebase is configured
        NotificationManager.shared.setup()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // Only set APNS token if Firebase is configured
        if FirebaseApp.app() != nil {
            Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        }
        print("🟢 [APNS] Registered with token")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 [APNS] Failed to register: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Only handle if Firebase is configured
        if FirebaseApp.app() != nil, Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }
}

@main
struct OurAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Firebase is configured in AppDelegate.didFinishLaunchingWithOptions
        // Widget sync moved to AppDelegate after Firebase is configured
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Task { @MainActor in
                let calendarManager = GoogleCalendarManager.shared
                let backgroundManager = BackgroundTaskManager.shared

                switch newPhase {
                case .active:
                    print("🟢 [APP LIFECYCLE] App became active")
                    // Refresh Firebase config for share extension (tokens expire after 1 hour)
                    updateSharedFirebaseConfig()

                    // Sync events to widget when app becomes active
                    WidgetDataManager.shared.syncFromFirebase()

                    // Restart periodic sync if needed
                    if calendarManager.isSignedIn && calendarManager.autoSyncEnabled {
                        print("🔄 [GOOGLE SYNC] Restarting periodic sync on app activation")
                        await calendarManager.handleAppBecameActive()
                    }

                    // Process any pending offline operations
                    if OfflineManager.shared.isOnline && OfflineManager.shared.pendingOperationsCount > 0 {
                        print("🔄 [OFFLINE] Processing pending operations on app activation")
                        OfflineManager.shared.processPendingOperationsInBackground()
                    }

                case .background:
                    print("🔴 [APP LIFECYCLE] App entering background")
                    // Stop timer to save resources
                    calendarManager.handleAppEnteredBackground()

                    // Schedule all background tasks for later execution
                    print("🔵 [BACKGROUND] Scheduling background tasks...")
                    backgroundManager.scheduleAllBackgroundTasks()

                    // Debug: Print scheduled tasks
                    #if DEBUG
                    backgroundManager.debugPrintScheduledTasks()
                    #endif

                case .inactive:
                    print("⚪️ [APP LIFECYCLE] App became inactive")

                @unknown default:
                    break
                }
            }
        }
    }
}

// MARK: - Pending Share Import Manager
class PendingShareImportManager: ObservableObject {
    static let shared = PendingShareImportManager()

    @Published var isProcessing = false
    @Published var pendingCount = 0
    @Published var processedCount = 0
    @Published var showImportAlert = false

    private let appGroupID = "group.com.ourapp"

    private init() {}

    /// Check for and process any pending uploads from Share Extension
    func checkAndProcessPendingUploads() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("⚠️ [SHARE IMPORT] Could not access app group container")
            return
        }

        // Read and display share extension diagnostic log
        let logURL = containerURL.appendingPathComponent("share_extension_log.txt")
        if let logContent = try? String(contentsOf: logURL, encoding: .utf8) {
            print("📜 [SHARE EXTENSION LOG]:")
            print(logContent)
            // Clear the log after reading
            try? FileManager.default.removeItem(at: logURL)
        }

        let manifestURL = containerURL.appendingPathComponent("pending_uploads.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            print("📋 [SHARE IMPORT] No pending uploads found")
            return
        }

        // Read manifest
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("⚠️ [SHARE IMPORT] Failed to read manifest")
            cleanupManifest()
            return
        }

        if manifest.isEmpty {
            cleanupManifest()
            return
        }

        print("📋 [SHARE IMPORT] Found \(manifest.count) pending uploads")

        Task { @MainActor in
            self.pendingCount = manifest.count
            self.processedCount = 0
            self.isProcessing = true
            self.showImportAlert = true
        }

        Task {
            await processManifest(manifest)
        }
    }

    private func processManifest(_ manifest: [[String: Any]]) async {
        for item in manifest {
            guard let path = item["path"] as? String,
                  let isVideo = item["isVideo"] as? Bool else {
                continue
            }

            let fileURL = URL(fileURLWithPath: path)

            guard FileManager.default.fileExists(atPath: path) else {
                print("⚠️ [SHARE IMPORT] File not found: \(path)")
                await incrementProcessedCount()
                continue
            }

            // Extract capturedAt from manifest if available
            var capturedAt: Date? = nil
            if let capturedAtTimestamp = item["capturedAt"] as? TimeInterval {
                capturedAt = Date(timeIntervalSince1970: capturedAtTimestamp)
            }

            // Get video-specific metadata from manifest
            let thumbnailPath = item["thumbnailPath"] as? String
            let duration = item["duration"] as? TimeInterval

            do {
                if isVideo {
                    try await uploadVideo(from: fileURL, capturedAt: capturedAt, thumbnailPath: thumbnailPath, duration: duration)
                } else {
                    try await uploadImage(from: fileURL, capturedAt: capturedAt)
                }
                print("✅ [SHARE IMPORT] Uploaded: \(fileURL.lastPathComponent)")
            } catch {
                print("🔴 [SHARE IMPORT] Failed to upload: \(error)")
            }

            // Clean up the temp file
            try? FileManager.default.removeItem(at: fileURL)
            // Clean up thumbnail if present
            if let thumbPath = thumbnailPath {
                try? FileManager.default.removeItem(atPath: thumbPath)
            }

            await incrementProcessedCount()
        }

        cleanupManifest()

        await MainActor.run {
            self.isProcessing = false
        }
    }

    private func uploadImage(from url: URL, capturedAt: Date? = nil) async throws {
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "ShareImport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        // Try to extract EXIF date if not provided
        var finalCapturedAt = capturedAt
        if finalCapturedAt == nil {
            finalCapturedAt = extractImageCapturedDate(from: data) ?? extractImageCapturedDate(from: url)
        }

        let resized = image.resized(toMaxDimension: 1920)
        guard let compressedData = resized.compressed(toMaxBytes: 1_000_000) else {
            throw NSError(domain: "ShareImport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
        }

        _ = try await FirebaseManager.shared.uploadPhoto(
            imageData: compressedData,
            caption: "",
            uploadedBy: UserIdentityManager.shared.currentUserName,
            capturedAt: finalCapturedAt
        )
    }

    /// Extract capture date from image EXIF metadata (from Data)
    private func extractImageCapturedDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            return formatter.date(from: dateString)
        }
        if let dateString = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            return formatter.date(from: dateString)
        }
        return nil
    }

    /// Extract capture date from image EXIF metadata (from URL)
    private func extractImageCapturedDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            return formatter.date(from: dateString)
        }
        if let dateString = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            return formatter.date(from: dateString)
        }
        return nil
    }

    private func uploadVideo(from url: URL, capturedAt: Date? = nil, thumbnailPath: String? = nil, duration: TimeInterval? = nil) async throws {
        // Process video and generate thumbnail (unless already provided)
        async let processTask = VideoCompressor.shared.processVideo(from: url)

        // Use provided thumbnail or generate one
        var thumbnailData: Data
        if let thumbPath = thumbnailPath,
           let existingThumbData = try? Data(contentsOf: URL(fileURLWithPath: thumbPath)) {
            thumbnailData = existingThumbData
        } else {
            let thumbnail = try await VideoCompressor.shared.generateThumbnail(from: url)
            let thumbnailResized = thumbnail.resized(toMaxDimension: 1920)
            guard let compressedThumb = thumbnailResized.compressed(toMaxBytes: 500_000) else {
                throw NSError(domain: "ShareImport", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to compress thumbnail"])
            }
            thumbnailData = compressedThumb
        }

        // Wait for video processing
        let processedVideo = try await processTask
        defer {
            if processedVideo.needsCleanup {
                try? FileManager.default.removeItem(at: processedVideo.fileURL)
            }
        }

        // Use provided capturedAt or extract from video metadata
        var finalCapturedAt = capturedAt
        if finalCapturedAt == nil {
            finalCapturedAt = await extractVideoCreationDate(from: url)
        }

        // Use provided duration or from processed video
        let finalDuration = duration ?? processedVideo.duration

        // Upload using file streaming (faster)
        _ = try await FirebaseManager.shared.uploadVideoFromFile(
            videoURL: processedVideo.fileURL,
            thumbnailData: thumbnailData,
            duration: finalDuration,
            caption: "",
            uploadedBy: UserIdentityManager.shared.currentUserName,
            capturedAt: finalCapturedAt
        )
    }

    /// Extract creation date from video metadata
    private func extractVideoCreationDate(from videoURL: URL) async -> Date? {
        let asset = AVURLAsset(url: videoURL)

        do {
            let metadata = try await asset.load(.commonMetadata)

            for item in metadata {
                if let key = item.commonKey, key == .commonKeyCreationDate {
                    if let dateValue = try await item.load(.dateValue) {
                        return dateValue
                    }
                    if let stringValue = try await item.load(.stringValue) {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = formatter.date(from: stringValue) {
                            return date
                        }
                        formatter.formatOptions = [.withInternetDateTime]
                        if let date = formatter.date(from: stringValue) {
                            return date
                        }
                    }
                }
            }
        } catch {
            print("⚠️ [SHARE IMPORT] Failed to load video metadata: \(error)")
        }

        return nil
    }

    @MainActor
    private func incrementProcessedCount() {
        self.processedCount += 1
    }

    private func cleanupManifest() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        let manifestURL = containerURL.appendingPathComponent("pending_uploads.json")
        try? FileManager.default.removeItem(at: manifestURL)

        // Also clean up the PendingUploads directory
        let pendingDir = containerURL.appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.removeItem(at: pendingDir)
    }
}

// MARK: - Share Extension Config
/// Writes Firebase configuration to shared container for Share Extension direct uploads
func shareFirebaseConfigWithExtension() {
    guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
        print("⚠️ [SHARE CONFIG] Could not access shared container")
        return
    }

    guard let app = FirebaseApp.app() else {
        print("⚠️ [SHARE CONFIG] Firebase not configured")
        return
    }

    let options = app.options

    // Get current user's ID token if authenticated
    Task {
        var idToken: String?
        if let user = Auth.auth().currentUser {
            do {
                idToken = try await user.getIDToken()
            } catch {
                print("⚠️ [SHARE CONFIG] Could not get ID token: \(error)")
            }
        }

        let config: [String: Any?] = [
            "storageBucket": options.storageBucket,
            "projectId": options.projectID,
            "apiKey": options.apiKey,
            "idToken": idToken
        ]

        // Filter out nil values
        let filteredConfig = config.compactMapValues { $0 }

        let configURL = sharedURL.appendingPathComponent("firebase_share_config.json")

        do {
            let data = try JSONSerialization.data(withJSONObject: filteredConfig, options: .prettyPrinted)
            try data.write(to: configURL)
            print("🟢 [SHARE CONFIG] Firebase config shared with extension")
        } catch {
            print("🔴 [SHARE CONFIG] Failed to write config: \(error)")
        }
    }
}

/// Updates the shared Firebase config (call when auth state changes)
func updateSharedFirebaseConfig() {
    shareFirebaseConfigWithExtension()
}

// MARK: - Root View (handles auth flow after Firebase is configured)
struct RootView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var shareImportManager = PendingShareImportManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingImportProgress = false

    var body: some View {
        Group {
            if authManager.isLoading {
                // Loading screen while checking auth state
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.93, blue: 1.0),
                            Color(red: 0.9, green: 0.85, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    ProgressView()
                        .tint(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            } else if authManager.showWelcome, let user = authManager.authenticatedUser {
                // Welcome screen after authentication
                WelcomeView(user: user) {
                    authManager.dismissWelcome()
                }
            } else if !authManager.isAuthenticated {
                // Authentication screen for first-time users
                AuthenticationView()
            } else {
                // Main app content
                ContentView()
                    .onOpenURL { url in
                        handleOpenURL(url)
                    }
                    .onAppear {
                        // Check for pending uploads when app appears
                        shareImportManager.checkAndProcessPendingUploads()
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        // Check for pending uploads when app becomes active
                        if newPhase == .active && oldPhase != .active {
                            shareImportManager.checkAndProcessPendingUploads()
                        }
                    }
                    .overlay {
                        // Import progress overlay
                        if shareImportManager.showImportAlert && shareImportManager.isProcessing {
                            ShareImportProgressView(
                                processed: shareImportManager.processedCount,
                                total: shareImportManager.pendingCount,
                                onDismiss: {
                                    shareImportManager.showImportAlert = false
                                }
                            )
                        }
                    }
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        // Handle Google Sign-In URLs
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }
    }
}

// MARK: - Share Import Progress View
struct ShareImportProgressView: View {
    let processed: Int
    let total: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Importing Media")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))

                ProgressView(value: Double(processed), total: Double(max(total, 1)))
                    .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.6, green: 0.4, blue: 0.85)))
                    .frame(width: 200)

                Text("\(processed) of \(total)")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                if processed >= total {
                    Button("Done") {
                        onDismiss()
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.6, green: 0.4, blue: 0.85))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.98, green: 0.96, blue: 1.0))
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 4)
        }
        .animation(.easeInOut, value: processed)
    }
}
