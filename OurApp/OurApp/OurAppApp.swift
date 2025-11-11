import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct OurAppApp: App {
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
        } else {
            print("🔴 [APP INIT ERROR] Firebase app is nil after configuration!")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Task { @MainActor in
                let manager = GoogleCalendarManager.shared

                switch newPhase {
                case .active:
                    print("🟢 [APP LIFECYCLE] App became active")
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
