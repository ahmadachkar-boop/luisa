import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var uploadManager = UploadProgressManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                VoiceMessagesView()
                    .tabItem {
                        Label("Voice Notes", systemImage: "waveform.circle.fill")
                    }
                    .tag(0)

                PhotoGalleryView()
                    .tabItem {
                        Label("Our Photos", systemImage: "heart.circle.fill")
                    }
                    .tag(1)

                CalendarView()
                    .tabItem {
                        Label("Our Plans", systemImage: "calendar.circle.fill")
                    }
                    .tag(2)

                WishListView()
                    .tabItem {
                        Label("Wish List", systemImage: "star.circle.fill")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.circle.fill")
                    }
                    .tag(4)
            }
            .accentColor(Color(red: 0.8, green: 0.7, blue: 1.0)) // Light purple

            // Global upload progress banner - visible across all tabs
            VStack {
                UploadProgressBanner()
                    .padding(.top, 50) // Below safe area
                Spacer()
            }
            .allowsHitTesting(uploadManager.isUploading || !uploadManager.recentlyCompletedBatches.isEmpty)
        }
    }
}

#Preview {
    ContentView()
}
