import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var uploadManager = UploadProgressManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
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

            // Global upload progress banner - visible across all tabs (above tab bar)
            VStack {
                Spacer()
                UploadProgressBanner()
                    .padding(.bottom, 50) // Above tab bar
            }
            .allowsHitTesting(uploadManager.isUploading || !uploadManager.recentlyCompletedBatches.isEmpty)
        }
    }
}

#Preview {
    ContentView()
}
