import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import GoogleSignIn
import UserNotifications

// MARK: - App Delegate for Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Setup notifications
        NotificationManager.shared.setup()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        print("🟢 [APNS] Registered with token")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 [APNS] Failed to register: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }
}

@main
struct OurAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        print("🔵 [APP INIT] Starting OurApp initialization")
        print("🔵 [APP INIT] Configuring Firebase...")
        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            print("🟢 [APP INIT] Firebase configured successfully")
            print("🟢 [APP INIT] Firebase app name: \(app.name)")
            if let bundleID = Bundle.main.bundleIdentifier {
                print("🟢 [APP INIT] Bundle ID: \(bundleID)")
            }

            // Sync events to widget at app startup
            print("🔵 [APP INIT] Syncing events to widget...")
            WidgetDataManager.shared.syncFromFirebase()
        } else {
            print("🔴 [APP INIT ERROR] Firebase app is nil after configuration!")
        }
    }

    var body: some Scene {
        WindowGroup {
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Task { @MainActor in
                let manager = GoogleCalendarManager.shared

                switch newPhase {
                case .active:
                    print("🟢 [APP LIFECYCLE] App became active")
                    // Sync events to widget when app becomes active
                    WidgetDataManager.shared.syncFromFirebase()

                    // Restart periodic sync if needed
                    if manager.isSignedIn && manager.autoSyncEnabled {
                        print("🔄 [GOOGLE SYNC] Restarting periodic sync on app activation")
                        await manager.handleAppBecameActive()
                    }

                case .background:
                    print("🔴 [APP LIFECYCLE] App entering background")
                    // Stop timer to save resources
                    manager.handleAppEnteredBackground()

                case .inactive:
                    print("⚪️ [APP LIFECYCLE] App became inactive")

                @unknown default:
                    break
                }
            }
        }
    }
}
