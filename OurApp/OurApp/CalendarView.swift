import SwiftUI
import PhotosUI
import MapKit

// Wrapper to make Int work with .fullScreenCover(item:)
struct CalendarPhotoIndex: Identifiable {
    let id = UUID()
    let value: Int
}

// Wrapper for recap card photo viewing
struct RecapPhotoData: Identifiable {
    let id = UUID()
    let photoURLs: [String]
    let initialIndex: Int
}

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showingAddEvent = false
    @State private var selectedDate = Date()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedEventForDetail: CalendarEvent?
    @State private var selectedTab = 0 // 0 = Upcoming, 1 = Memories
    @State private var currentMonth = Date()
    @State private var selectedDay: Date? = nil // For filtering by specific day
    @State private var summaryCardExpanded = true // Start expanded
    @State private var recapPhotoData: RecapPhotoData?
    @State private var countdownBannerIndex = 0
    @State private var countdownResetTimer: Timer?

    var body: some View {
        NavigationView {
            ZStack {
                // Sophisticated background
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 1.0),
                        Color(red: 0.96, green: 0.94, blue: 0.99),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header with month selector
                        VStack(spacing: 16) {
                            // Month navigation
                            HStack {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.title3)
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                        .frame(width: 44, height: 44)
                                }

                                Spacer()

                                VStack(spacing: 2) {
                                    Text(currentMonth, format: .dateTime.month(.wide))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))

                                    Text(currentMonth, format: .dateTime.year())
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                }

                                Spacer()

                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                                    }
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.title3)
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                        .frame(width: 44, height: 44)
                                }
                            }
                            .padding(.horizontal)

                            // Countdown Banner - Swipeable
                            if !viewModel.upcomingEvents.isEmpty {
                                let upcomingToShow = Array(viewModel.upcomingEvents.prefix(5))

                                TabView(selection: $countdownBannerIndex) {
                                    ForEach(Array(upcomingToShow.enumerated()), id: \.element.id) { index, event in
                                        ModernCountdownBanner(event: event, onTap: {
                                            selectedEventForDetail = event
                                        })
                                        .tag(index)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: upcomingToShow.count > 1 ? .automatic : .never))
                                .frame(height: 80)
                                .padding(.horizontal)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .onChange(of: countdownBannerIndex) { oldValue, newValue in
                                    // Reset timer when user manually swipes
                                    resetCountdownTimer()
                                }
                                .onAppear {
                                    startCountdownResetTimer()
                                }
                                .onDisappear {
                                    countdownResetTimer?.invalidate()
                                    countdownResetTimer = nil
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                        // Calendar Grid
                        CalendarGridView(
                            currentMonth: currentMonth,
                            events: viewModel.events,
                            selectedDay: $selectedDay,
                            selectedTab: $selectedTab
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 16)

                        // Month Summary Card (only for past months)
                        if isMonthInPast(currentMonth) {
                            MonthSummaryCard(
                                month: currentMonth,
                                events: eventsForCurrentMonth(),
                                isExpanded: $summaryCardExpanded,
                                onPhotoTap: { photoURLs, index in
                                    recapPhotoData = RecapPhotoData(photoURLs: photoURLs, initialIndex: index)
                                }
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                        }

                        // Custom Tab Selector
                        ModernTabSelector(selectedTab: $selectedTab)
                            .padding(.horizontal)
                            .padding(.bottom, 12)

                        // Filter indicator
                        if let selectedDay = selectedDay {
                            FilterHeaderView(
                                selectedDay: selectedDay,
                                eventCount: filteredEvents().count,
                                onClear: {
                                    withAnimation(.spring(response: 0.3)) {
                                        self.selectedDay = nil
                                    }
                                }
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Events list
                        let eventsToShow = filteredEvents()

                        if eventsToShow.isEmpty {
                            EmptyStateView(isUpcoming: selectedTab == 0)
                                .padding(.top, 60)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(eventsToShow) { event in
                                    ModernEventCard(
                                        event: event,
                                        onTap: {
                                            selectedEventForDetail = event
                                        },
                                        onDelete: {
                                            Task {
                                                do {
                                                    try await viewModel.deleteEvent(event)
                                                } catch {
                                                    errorMessage = "Failed to delete event: \(error.localizedDescription)"
                                                    showError = true
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 100)
                        }
                    }
                }

                // Floating action button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingAddEvent = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("New Plan")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.4, blue: 0.95),
                                        Color(red: 0.55, green: 0.3, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(30)
                            .shadow(color: Color.purple.opacity(0.4), radius: 15, x: 0, y: 8)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Our Plans")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(initialDate: selectedDate) { event in
                    do {
                        try await viewModel.addEvent(event)
                    } catch {
                        errorMessage = "Failed to add event: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
            .sheet(item: $selectedEventForDetail) { event in
                EventDetailView(event: event, onDelete: {
                    Task {
                        do {
                            try await viewModel.deleteEvent(event)
                        } catch {
                            errorMessage = "Failed to delete event: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                })
            }
            .fullScreenCover(item: $recapPhotoData) { photoData in
                if !photoData.photoURLs.isEmpty {
                    FullScreenPhotoViewer(
                        photoURLs: photoData.photoURLs,
                        initialIndex: photoData.initialIndex,
                        onDismiss: { recapPhotoData = nil },
                        onDelete: { _ in
                            // Recap photos are read-only, no delete
                        }
                    )
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: currentMonth) { oldValue, newValue in
                // Reset day filter when month changes
                withAnimation(.spring(response: 0.3)) {
                    selectedDay = nil
                }
            }
            .onChange(of: viewModel.upcomingEvents.count) { oldValue, newValue in
                // Reset countdown banner index if events changed
                if countdownBannerIndex >= newValue {
                    countdownBannerIndex = 0
                }
            }
        }
    }

    // MARK: - Helper Functions

    func filteredEvents() -> [CalendarEvent] {
        let baseEvents = selectedTab == 0 ? viewModel.upcomingEvents : viewModel.pastEvents

        // Filter by selected month
        let monthFiltered = baseEvents.filter { event in
            Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
        }

        // Further filter by selected day if one is selected
        if let selectedDay = selectedDay {
            return monthFiltered.filter { event in
                Calendar.current.isDate(event.date, equalTo: selectedDay, toGranularity: .day)
            }
        }

        return monthFiltered
    }

    func eventsForCurrentMonth() -> [CalendarEvent] {
        return viewModel.events.filter { event in
            Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
        }
    }

    func isMonthInPast(_ date: Date) -> Bool {
        let now = Date()
        let currentMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
        let selectedMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))!
        return selectedMonthStart < currentMonthStart
    }

    func startCountdownResetTimer() {
        countdownResetTimer?.invalidate()
        countdownResetTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                countdownBannerIndex = 0
            }
        }
    }

    func resetCountdownTimer() {
        startCountdownResetTimer()
    }
}

// MARK: - Modern Countdown Banner
struct ModernCountdownBanner: View {
    let event: CalendarEvent
    let onTap: () -> Void
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: event.isSpecial ? "star.fill" : "clock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(timeRemaining)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Glassmorphism effect
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: event.isSpecial ?
                                    [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.65, green: 0.25, blue: 0.9)] :
                                    [Color(red: 0.6, green: 0.4, blue: 0.85), Color(red: 0.5, green: 0.3, blue: 0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Subtle glow
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            )
            .shadow(color: event.isSpecial ? Color.purple.opacity(0.3) : Color.black.opacity(0.1),
                    radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            updateCountdown()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                updateCountdown()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    func updateCountdown() {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: event.date)

        if let days = components.day, let hours = components.hour, let minutes = components.minute {
            if days > 0 {
                timeRemaining = "\(days)d \(hours)h away"
            } else if hours > 0 {
                timeRemaining = "\(hours)h \(minutes)m away"
            } else {
                timeRemaining = "\(minutes)m away"
            }
        }
    }
}

// MARK: - Modern Tab Selector
struct ModernTabSelector: View {
    @Binding var selectedTab: Int
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<2) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 8) {
                        Text(index == 0 ? "Upcoming" : "Memories")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(selectedTab == index ?
                                Color(red: 0.6, green: 0.4, blue: 0.85) :
                                Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.6)
                            )

                        if selectedTab == index {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.7, green: 0.4, blue: 0.95),
                                            Color(red: 0.55, green: 0.3, blue: 0.85)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "tab", in: animation)
                        } else {
                            Capsule()
                                .fill(Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Modern Event Card
struct ModernEventCard: View {
    let event: CalendarEvent
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                // Date badge
                VStack(spacing: 4) {
                    Text(event.date, format: .dateTime.day())
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text(event.date, format: .dateTime.month(.abbreviated).year())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .textCase(.uppercase)
                }
                .frame(width: 70, height: 70)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: event.isSpecial ?
                                        [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.65, green: 0.25, blue: 0.9)] :
                                        [Color(red: 0.6, green: 0.4, blue: 0.85), Color(red: 0.5, green: 0.3, blue: 0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        if event.isSpecial {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                        }
                    }
                )
                .shadow(color: event.isSpecial ? Color.purple.opacity(0.4) : Color.black.opacity(0.15),
                        radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    // Title row
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))

                        if event.isSpecial {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.8, green: 0.5, blue: 0.95))
                        }

                        Spacer()

                        if !event.photoURLs.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "photo.fill")
                                    .font(.caption2)
                                Text("\(event.photoURLs.count)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                    }

                    // Time
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(event.date, format: .dateTime.hour().minute())
                            .font(.system(size: 14))
                    }
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                    // Description
                    if !event.description.isEmpty {
                        Text(event.description)
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            .lineLimit(2)
                    }

                    // Location
                    if !event.location.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption)
                            Text(event.location)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }
                }

                VStack(spacing: 12) {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            ZStack {
                // Glassmorphism card
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)

                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.99, green: 0.97, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Border
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        event.isSpecial ?
                            LinearGradient(
                                colors: [Color.purple.opacity(0.2), Color.pink.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: event.isSpecial ? Color.purple.opacity(0.15) : Color.black.opacity(0.06),
                radius: 15, x: 0, y: 4)
        .alert("Delete Event?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This will remove '\(event.title)' from your plans")
        }
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let isUpcoming: Bool

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.9, blue: 1.0),
                                Color(red: 0.9, green: 0.85, blue: 0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.purple.opacity(0.1), radius: 20, x: 0, y: 10)

                Image(systemName: isUpcoming ? "calendar.badge.plus" : "heart.text.square")
                    .font(.system(size: 50))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
            }

            VStack(spacing: 8) {
                Text(isUpcoming ? "No plans yet" : "No memories yet")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                Text(isUpcoming ? "Create your first plan together" : "Past events will appear here")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Rest of the existing code (EventDetailView, AddEventView, etc.)

struct EventDetailView: View {
    let event: CalendarEvent
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteAlert = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isUploadingPhotos = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var currentEvent: CalendarEvent
    @State private var selectedPhotoIndex: CalendarPhotoIndex?
    @State private var selectionMode = false
    @State private var selectedPhotoIndices: Set<Int> = []
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var savedPhotoCount = 0

    init(event: CalendarEvent, onDelete: @escaping () -> Void) {
        self.event = event
        self.onDelete = onDelete
        _currentEvent = State(initialValue: event)
    }

    var isPastEvent: Bool {
        event.date < Date()
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: event.isSpecial ?
                        [Color(red: 0.98, green: 0.9, blue: 1.0), Color.white] :
                        [Color(red: 0.95, green: 0.9, blue: 1.0), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Date display
                        VStack(spacing: 8) {
                            Text(event.date, format: .dateTime.day())
                                .font(.system(size: 60, weight: .bold))
                                .foregroundColor(.white)

                            Text(event.date, format: .dateTime.month(.wide).year())
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.95))

                            Text(event.date, format: .dateTime.weekday(.wide))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .background(
                            LinearGradient(
                                colors: event.isSpecial ?
                                    [Color(red: 0.8, green: 0.3, blue: 0.7), Color(red: 0.6, green: 0.2, blue: 0.9)] :
                                    [Color(red: 0.5, green: 0.3, blue: 0.8), Color(red: 0.4, green: 0.2, blue: 0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: event.isSpecial ? Color.purple.opacity(0.4) : Color.black.opacity(0.2),
                                radius: 15, x: 0, y: 5)
                        .padding(.horizontal)

                        // Photos
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Photos 📸")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                Spacer()

                                // Add photos button for past events
                                if isPastEvent {
                                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                                        HStack(spacing: 4) {
                                            if isUploadingPhotos {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Add")
                                                    .font(.caption)
                                            }
                                        }
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.95, green: 0.9, blue: 1.0))
                                        .cornerRadius(15)
                                    }
                                    .disabled(isUploadingPhotos)
                                }
                            }
                            .padding(.horizontal)

                            if !currentEvent.photoURLs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(currentEvent.photoURLs.enumerated()), id: \.offset) { index, photoURL in
                                            ZStack(alignment: .topTrailing) {
                                                CachedAsyncImage(url: URL(string: photoURL)) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 250, height: 250)
                                                        .clipShape(RoundedRectangle(cornerRadius: 15))
                                                } placeholder: {
                                                    RoundedRectangle(cornerRadius: 15)
                                                        .fill(Color.gray.opacity(0.2))
                                                        .frame(width: 250, height: 250)
                                                        .overlay(ProgressView())
                                                }
                                                .overlay(
                                                    selectionMode ?
                                                        RoundedRectangle(cornerRadius: 15)
                                                            .stroke(selectedPhotoIndices.contains(index) ? Color.blue : Color.clear, lineWidth: 3)
                                                    : nil
                                                )
                                                .contentShape(RoundedRectangle(cornerRadius: 15))
                                                .onTapGesture {
                                                    if selectionMode {
                                                        if selectedPhotoIndices.contains(index) {
                                                            selectedPhotoIndices.remove(index)
                                                        } else {
                                                            selectedPhotoIndices.insert(index)
                                                        }
                                                    } else {
                                                        selectedPhotoIndex = CalendarPhotoIndex(value: index)
                                                    }
                                                }
                                                .onLongPressGesture(minimumDuration: 0.5) {
                                                    if !selectionMode {
                                                        selectionMode = true
                                                        selectedPhotoIndices.insert(index)
                                                    }
                                                }

                                                // Checkmark overlay
                                                if selectionMode {
                                                    Image(systemName: selectedPhotoIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                                                        .font(.title2)
                                                        .foregroundColor(selectedPhotoIndices.contains(index) ? .blue : .white)
                                                        .shadow(radius: 2)
                                                        .padding(10)
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            } else if isPastEvent {
                                Text("Add photos to remember this moment")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                    .italic()
                                    .padding(.horizontal)
                            }
                        }
                        .onChange(of: photoPickerItems) { oldItems, newItems in
                            Task {
                                await uploadPhotos(newItems)
                            }
                        }

                        // Event details
                        VStack(alignment: .leading, spacing: 20) {
                            // Title
                            HStack {
                                Text(event.title)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))

                                if event.isSpecial {
                                    HStack(spacing: 4) {
                                        Text("✨")
                                        Text("💜")
                                        Text("✨")
                                    }
                                }
                            }

                            Divider()

                            // Description
                            if !event.description.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Details", systemImage: "text.alignleft")
                                        .font(.headline)
                                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                    Text(event.description)
                                        .font(.body)
                                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                                }
                            }

                            // Location
                            if !event.location.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Location", systemImage: "mappin.circle.fill")
                                        .font(.headline)
                                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                    Button {
                                        openInMaps()
                                    } label: {
                                        HStack {
                                            Text(event.location)
                                                .font(.body)
                                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                                            Spacer()
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.caption)
                                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                                        }
                                    }
                                }
                            }

                            // Time
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Time", systemImage: "clock.fill")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                Text(event.date, format: .dateTime.hour().minute())
                                    .font(.body)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            }

                            Divider()

                            // Creator
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(Color(red: 0.7, green: 0.4, blue: 0.9))
                                Text("Added by \(event.createdBy)")
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            selectionMode = false
                            selectedPhotoIndices.removeAll()
                        }
                        .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button(action: saveSelectedPhotos) {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))
                            }
                            .disabled(selectedPhotoIndices.isEmpty)

                            Button(action: deleteSelectedPhotos) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedPhotoIndices.isEmpty)
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Delete Event?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will remove '\(event.title)' from your plans")
            }
            .alert("Upload Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Saved!", isPresented: $showingSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(savedPhotoCount) photo\(savedPhotoCount == 1 ? "" : "s") saved to your library")
            }
            .alert("Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .fullScreenCover(item: $selectedPhotoIndex) { photoIndex in
                FullScreenPhotoViewer(
                    photoURLs: currentEvent.photoURLs,
                    initialIndex: photoIndex.value,
                    onDismiss: { selectedPhotoIndex = nil },
                    onDelete: { indexToDelete in
                        if indexToDelete < currentEvent.photoURLs.count {
                            var updatedPhotoURLs = currentEvent.photoURLs
                            updatedPhotoURLs.remove(at: indexToDelete)
                            Task {
                                var updatedEvent = currentEvent
                                updatedEvent.photoURLs = updatedPhotoURLs
                                try? await FirebaseManager.shared.updateCalendarEvent(updatedEvent)
                                await MainActor.run {
                                    currentEvent.photoURLs = updatedPhotoURLs
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    private func saveSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

        let totalCount = selectedPhotoIndices.count

        Task {
            var savedCount = 0
            var errorOccurred = false

            for index in selectedPhotoIndices.sorted() {
                guard index < currentEvent.photoURLs.count else { continue }
                let photoURL = currentEvent.photoURLs[index]

                // Load image
                if let cachedImage = ImageCache.shared.get(forKey: photoURL) {
                    let imageSaver = ImageSaver()
                    imageSaver.successHandler = {
                        savedCount += 1
                        if savedCount == totalCount {
                            Task { @MainActor in
                                savedPhotoCount = totalCount
                                showingSaveSuccess = true
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            Task { @MainActor in
                                saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                    }
                    imageSaver.writeToPhotoAlbum(image: cachedImage)
                } else if let url = URL(string: photoURL),
                          let data = try? Data(contentsOf: url),
                          let image = UIImage(data: data) {
                    ImageCache.shared.set(image, forKey: photoURL)
                    let imageSaver = ImageSaver()
                    imageSaver.successHandler = {
                        savedCount += 1
                        if savedCount == totalCount {
                            Task { @MainActor in
                                savedPhotoCount = totalCount
                                showingSaveSuccess = true
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            Task { @MainActor in
                                saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                    }
                    imageSaver.writeToPhotoAlbum(image: image)
                }
            }
        }
    }

    private func deleteSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

        Task {
            var updatedPhotoURLs = currentEvent.photoURLs
            for index in selectedPhotoIndices.sorted().reversed() {
                guard index < updatedPhotoURLs.count else { continue }
                updatedPhotoURLs.remove(at: index)
            }

            var updatedEvent = currentEvent
            updatedEvent.photoURLs = updatedPhotoURLs
            try? await FirebaseManager.shared.updateCalendarEvent(updatedEvent)

            await MainActor.run {
                currentEvent.photoURLs = updatedPhotoURLs
                selectionMode = false
                selectedPhotoIndices.removeAll()
            }
        }
    }

    func openInMaps() {
        let query = event.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(query)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webURL = URL(string: "https://maps.apple.com/?q=\(query)") {
                UIApplication.shared.open(webURL)
            }
        }
    }

    func uploadPhotos(_ items: [PhotosPickerItem]) async {
        print("🔵 [UPLOAD START] Beginning photo upload for \(items.count) items")
        isUploadingPhotos = true
        var newPhotoURLs: [String] = []
        var uploadErrors: [String] = []

        for (index, item) in items.enumerated() {
            print("🔵 [UPLOAD] Processing item \(index + 1)/\(items.count)")

            do {
                print("🔵 [UPLOAD] Loading image data...")
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    print("🔴 [UPLOAD ERROR] Failed to load image data for item \(index + 1)")
                    uploadErrors.append("Failed to load image \(index + 1)")
                    continue
                }

                print("🔵 [UPLOAD] Processing image: \(uiImage.size)")

                // Resize and compress
                let resized = uiImage.resized(toMaxDimension: 1920)
                print("🔵 [UPLOAD] Resized to: \(resized.size)")

                guard let compressedData = resized.compressed(toMaxBytes: 1_000_000) else {
                    print("🔴 [UPLOAD ERROR] Failed to compress image \(index + 1)")
                    uploadErrors.append("Failed to compress image \(index + 1)")
                    continue
                }

                print("🔵 [UPLOAD] Compressed size: \(compressedData.count) bytes")
                print("🔵 [UPLOAD] Uploading to Firebase...")

                let photoURL = try await FirebaseManager.shared.uploadEventPhoto(imageData: compressedData)
                print("🟢 [UPLOAD SUCCESS] Photo \(index + 1) uploaded: \(photoURL)")
                newPhotoURLs.append(photoURL)

            } catch {
                print("🔴 [UPLOAD ERROR] Failed to upload photo \(index + 1): \(error)")
                uploadErrors.append("Failed to upload photo \(index + 1): \(error.localizedDescription)")
            }
        }

        print("🔵 [UPLOAD] Upload complete. Success: \(newPhotoURLs.count), Errors: \(uploadErrors.count)")

        // Update the event with new photo URLs
        if !newPhotoURLs.isEmpty {
            var updatedEvent = currentEvent
            updatedEvent.photoURLs.append(contentsOf: newPhotoURLs)

            print("🔵 [UPDATE] Updating event with \(updatedEvent.photoURLs.count) total photos")

            do {
                try await FirebaseManager.shared.updateCalendarEvent(updatedEvent)
                print("🟢 [UPDATE SUCCESS] Event updated successfully")

                await MainActor.run {
                    currentEvent.photoURLs = updatedEvent.photoURLs
                    print("🔵 [UI UPDATE] UI updated with new photos")
                }
            } catch {
                print("🔴 [UPDATE ERROR] Failed to update event: \(error)")
                errorMessage = "Failed to update event: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }

        if !uploadErrors.isEmpty {
            errorMessage = uploadErrors.joined(separator: "\n")
            showingErrorAlert = true
        }

        isUploadingPhotos = false
        photoPickerItems = []
    }
}

// MARK: - Add Event View (keeping existing)
struct AddEventView: View {
    @Environment(\.dismiss) var dismiss
    let initialDate: Date
    let onSave: (CalendarEvent) async -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var date: Date
    @State private var isSpecial = false
    @State private var isSaving = false

    init(initialDate: Date, onSave: @escaping (CalendarEvent) async -> Void) {
        self.initialDate = initialDate
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("When & Where") {
                    DatePicker("Date & Time", selection: $date)
                    TextField("Location (optional)", text: $location)
                }

                Section {
                    Toggle("Special Event 💜", isOn: $isSpecial)
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                await saveEvent()
                            }
                        }
                        .disabled(title.isEmpty)
                    }
                }
            }
        }
    }

    func saveEvent() async {
        isSaving = true

        let event = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            description: description,
            date: date,
            location: location,
            createdBy: "You",
            isSpecial: isSpecial,
            photoURLs: []
        )

        await onSave(event)
        isSaving = false
        dismiss()
    }
}

// MARK: - View Models
class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []

    private let firebaseManager = FirebaseManager.shared

    var upcomingEvents: [CalendarEvent] {
        let now = Date()
        return events.filter { $0.date >= now }.sorted { $0.date < $1.date }
    }

    var pastEvents: [CalendarEvent] {
        let now = Date()
        return events.filter { $0.date < now }.sorted { $0.date > $1.date }
    }

    init() {
        loadEvents()
    }

    func loadEvents() {
        Task {
            for try await events in firebaseManager.getCalendarEvents() {
                await MainActor.run {
                    self.events = events
                }
            }
        }
    }

    func addEvent(_ event: CalendarEvent) async throws {
        try await firebaseManager.addCalendarEvent(event)
    }

    func deleteEvent(_ event: CalendarEvent) async throws {
        try await firebaseManager.deleteCalendarEvent(event)
    }
}

// MARK: - Calendar Grid View
struct CalendarGridView: View {
    let currentMonth: Date
    let events: [CalendarEvent]
    @Binding var selectedDay: Date?
    @Binding var selectedTab: Int
    @State private var hoveredDay: Date?

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 12) {
            // Days of week header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        CalendarDayCell(
                            date: date,
                            events: eventsForDay(date),
                            isSelected: selectedDay != nil && calendar.isDate(date, inSameDayAs: selectedDay!),
                            isToday: calendar.isDateInToday(date),
                            onTap: {
                                handleDayTap(date: date)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else {
            return []
        }

        let firstDayOfWeek = calendar.firstWeekday
        let leadingEmptyDays = (firstWeekday - firstDayOfWeek + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)

        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return days
    }

    func eventsForDay(_ date: Date) -> [CalendarEvent] {
        return events.filter { event in
            calendar.isDate(event.date, inSameDayAs: date)
        }
    }

    func handleDayTap(date: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedDay != nil && calendar.isDate(date, inSameDayAs: selectedDay!) {
                selectedDay = nil // Deselect if tapping same day
            } else {
                selectedDay = date

                // Auto-switch tabs based on date
                let isPastDate = date < Date()
                if isPastDate && selectedTab == 0 {
                    // Switch to Memories tab for past dates
                    selectedTab = 1
                } else if !isPastDate && selectedTab == 1 {
                    // Switch to Upcoming tab for future dates
                    selectedTab = 0
                }
            }
        }
    }
}

// MARK: - Calendar Day Cell
struct CalendarDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    @State private var showTooltip = false

    var body: some View {
        Button(action: {
            if events.isEmpty {
                // Show brief feedback for empty days
                withAnimation(.spring(response: 0.2)) {
                    showTooltip = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.spring(response: 0.2)) {
                        showTooltip = false
                    }
                }
            } else {
                onTap()
            }
        }) {
            VStack(spacing: 4) {
                // Day number
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(
                        isSelected ? .white :
                        isToday ? Color(red: 0.6, green: 0.4, blue: 0.85) :
                        events.isEmpty ? Color(red: 0.7, green: 0.6, blue: 0.8).opacity(0.5) :
                        Color(red: 0.3, green: 0.2, blue: 0.5)
                    )

                // Event dots
                if !events.isEmpty {
                    EventDotsView(events: events)
                } else if showTooltip {
                    Text("·")
                        .font(.system(size: 8))
                        .foregroundColor(Color.gray.opacity(0.3))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.4, blue: 0.95),
                                        Color(red: 0.55, green: 0.3, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(red: 0.6, green: 0.4, blue: 0.85), lineWidth: 2)
                    } else if events.isEmpty && showTooltip {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.05))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Event Dots View (clustered layout for multiple events)
struct EventDotsView: View {
    let events: [CalendarEvent]

    var body: some View {
        if events.count == 1 {
            // Single dot
            Circle()
                .fill(dotColor(for: events[0]))
                .frame(width: 5, height: 5)
        } else if events.count == 2 {
            // Two dots side by side
            HStack(spacing: 2) {
                Circle()
                    .fill(dotColor(for: events[0]))
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(dotColor(for: events[1]))
                    .frame(width: 4, height: 4)
            }
        } else {
            // Three dots arranged diagonally for 3+
            ZStack {
                HStack(spacing: 2) {
                    Circle()
                        .fill(dotColor(for: events[0]))
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 1)
                    Circle()
                        .fill(dotColor(for: events[1]))
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: -1)
                    if events.count > 2 {
                        Circle()
                            .fill(dotColor(for: events[2]))
                            .frame(width: 3.5, height: 3.5)
                            .offset(y: 1)
                    }
                }
            }
        }
    }

    func dotColor(for event: CalendarEvent) -> Color {
        let isPast = event.date < Date()

        if event.isSpecial {
            return isPast ?
                Color(red: 0.85, green: 0.35, blue: 0.75) : // Gold/pink for special past
                Color(red: 0.9, green: 0.6, blue: 0.2) // Gold for special upcoming
        } else {
            return isPast ?
                Color(red: 0.85, green: 0.4, blue: 0.9) : // Pink for past with photos
                Color(red: 0.6, green: 0.4, blue: 0.85) // Purple for upcoming
        }
    }
}

// MARK: - Month Summary Card
struct MonthSummaryCard: View {
    let month: Date
    let events: [CalendarEvent]
    @Binding var isExpanded: Bool
    let onPhotoTap: ([String], Int) -> Void

    @State private var displayedPhotoURLs: [String] = []
    @State private var shuffleTimer: Timer?

    var eventCount: Int { events.count }
    var photoCount: Int { events.flatMap { $0.photoURLs }.count }
    var specialEventCount: Int { events.filter { $0.isSpecial }.count }
    var allPhotoURLs: [String] {
        events.flatMap { $0.photoURLs }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.9, green: 0.85, blue: 0.98),
                                        Color(red: 0.85, green: 0.75, blue: 0.95)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(month, format: .dateTime.month(.wide).year())")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        HStack(spacing: 12) {
                            Text("\(eventCount) plan\(eventCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                            if photoCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 10))
                                    Text("\(photoCount)")
                                        .font(.caption)
                                }
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }

                            if specialEventCount > 0 {
                                Text("\(specialEventCount) special moment\(specialEventCount == 1 ? "" : "s") ✨")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.7, green: 0.4, blue: 0.9))
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content
            if isExpanded && !allPhotoURLs.isEmpty {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)

                    // Photo collage
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(displayedPhotoURLs.enumerated()), id: \.offset) { index, photoURL in
                            Button(action: {
                                // Find the index in allPhotoURLs
                                if let globalIndex = allPhotoURLs.firstIndex(of: photoURL) {
                                    onPhotoTap(allPhotoURLs, globalIndex)
                                }
                            }) {
                                CachedAsyncImage(url: URL(string: photoURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 140)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 140)
                                        .overlay(ProgressView())
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .contentShape(Rectangle())
                            .id(photoURL) // For animation
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    if displayedPhotoURLs.isEmpty {
                        initializePhotos()
                    }
                    startShuffleTimer()
                }
                .onDisappear {
                    shuffleTimer?.invalidate()
                    shuffleTimer = nil
                }
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)

                // Subtle "archived" overlay
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.9, blue: 0.98).opacity(0.5),
                                Color.white.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(red: 0.85, green: 0.75, blue: 0.95), lineWidth: 1)
            }
        )
        .shadow(color: Color.purple.opacity(0.08), radius: 12, x: 0, y: 4)
        .onChange(of: isExpanded) { oldValue, newValue in
            // Initialize photos when card is expanded
            if newValue && displayedPhotoURLs.isEmpty {
                initializePhotos()
            }
        }
    }

    // MARK: - Helper Functions

    func initializePhotos() {
        guard !allPhotoURLs.isEmpty else { return }

        // Initialize with first 4 photos (or less if not enough)
        displayedPhotoURLs = Array(allPhotoURLs.prefix(4))
    }

    func startShuffleTimer() {
        guard allPhotoURLs.count > 4 else { return } // Only shuffle if we have more than 4 photos

        shuffleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            shuffleRandomPhoto()
        }
    }

    func shuffleRandomPhoto() {
        guard allPhotoURLs.count > 4, displayedPhotoURLs.count == 4 else { return }

        withAnimation(.easeInOut(duration: 0.5)) {
            // Pick a random position to replace (0-3)
            let randomPosition = Int.random(in: 0..<4)

            // Get photos not currently displayed
            let availablePhotos = allPhotoURLs.filter { !displayedPhotoURLs.contains($0) }

            guard !availablePhotos.isEmpty else { return }

            // Pick a random photo from available ones
            let newPhoto = availablePhotos.randomElement()!

            // Replace the photo at random position
            displayedPhotoURLs[randomPosition] = newPhoto
        }
    }
}

// MARK: - Filter Header View
struct FilterHeaderView: View {
    let selectedDay: Date
    let eventCount: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay, format: .dateTime.month(.wide).day())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                if eventCount > 0 {
                    Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                } else {
                    Text("No events")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }
            }

            Spacer()

            Button(action: onClear) {
                HStack(spacing: 4) {
                    Text("Show All")
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 0.95, green: 0.9, blue: 1.0))
                .cornerRadius(12)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

#Preview {
    CalendarView()
}
