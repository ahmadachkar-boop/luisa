import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import GoogleSignIn
import UserNotifications
import BackgroundTasks

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

// MARK: - Root View (handles auth flow after Firebase is configured)
struct RootView: View {
    @StateObject private var authManager = AuthenticationManager.shared

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
                        GIDSignIn.sharedInstance.handle(url)
                    }
            }
        }
    }
}
