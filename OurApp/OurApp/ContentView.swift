import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    private let appVersion = "1.3.1"

    var body: some View {
        ZStack {
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
            }
            .accentColor(Color(red: 0.8, green: 0.7, blue: 1.0)) // Light purple

            // Version number indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.trailing, 8)
                        .padding(.bottom, 50) // Above tab bar
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
