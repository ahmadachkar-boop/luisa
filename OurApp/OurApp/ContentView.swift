import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var uploadManager = UploadProgressManager.shared

    // Reset triggers - increment to signal each view to return to root
    @State private var voiceNotesResetTrigger = 0
    @State private var photosResetTrigger = 0
    @State private var calendarResetTrigger = 0
    @State private var wishListResetTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                VoiceMessagesView(resetTrigger: $voiceNotesResetTrigger)
                    .tabItem {
                        Label("Voice Notes", systemImage: "waveform.circle.fill")
                    }
                    .tag(0)

                PhotoGalleryView(resetTrigger: $photosResetTrigger)
                    .tabItem {
                        Label("Our Photos", systemImage: "heart.circle.fill")
                    }
                    .tag(1)

                CalendarView(resetTrigger: $calendarResetTrigger)
                    .tabItem {
                        Label("Our Plans", systemImage: "calendar.circle.fill")
                    }
                    .tag(2)

                WishListView(resetTrigger: $wishListResetTrigger)
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

            // Invisible tap interceptors over each tab bar item
            TabBarTapInterceptor(
                selectedTab: $selectedTab,
                onSameTabTapped: { tab in
                    switch tab {
                    case 0: voiceNotesResetTrigger += 1
                    case 1: photosResetTrigger += 1
                    case 2: calendarResetTrigger += 1
                    case 3: wishListResetTrigger += 1
                    default: break
                    }
                }
            )
        }
    }
}

// MARK: - Tab Bar Tap Interceptor
struct TabBarTapInterceptor: View {
    @Binding var selectedTab: Int
    let onSameTabTapped: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<5) { index in
                    Color.clear
                        .frame(width: geometry.size.width / 5, height: 50)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedTab == index {
                                // Same tab tapped - trigger reset
                                onSameTabTapped(index)
                            } else {
                                // Different tab - just switch
                                selectedTab = index
                            }
                        }
                }
            }
        }
        .frame(height: 50)
    }
}

#Preview {
    ContentView()
}
