import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct OurAppApp: App {
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
    }
}
