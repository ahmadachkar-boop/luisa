import SwiftUI
import PhotosUI
import MapKit
import WeatherKit
import CoreLocation
import ImageIO
import WidgetKit

// MARK: - Timeout Helper
struct TimeoutError: Error {}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Design Constants
extension CGFloat {
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusMedium: CGFloat = 16
    static let cornerRadiusLarge: CGFloat = 24
}

// MARK: - Timer Manager
class TimerManager: ObservableObject {
    static let shared = TimerManager()

    private var timers: [String: Timer] = [:]

    private init() {}

    func schedule(id: String, interval: TimeInterval, repeats: Bool = true, action: @escaping () -> Void) {
        // Invalidate existing timer if any
        invalidate(id: id)

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            action()
        }
        timers[id] = timer
    }

    func invalidate(id: String) {
        timers[id]?.invalidate()
        timers[id] = nil
    }

    func invalidateAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    deinit {
        invalidateAll()
    }
}

// MARK: - Weather Service
class WeatherService {
    static let shared = WeatherService()
    private let weatherService = WeatherKit.WeatherService.shared
    private let geocoder = CLGeocoder()

    private init() {}

    func fetchWeatherForEvent(location: String, date: Date) async -> String? {
        // Only fetch weather for future events within the next 10 days
        guard date > Date(),
              date.timeIntervalSinceNow < 10 * 24 * 60 * 60 else {
            return nil
        }

        do {
            // Geocode the location to get coordinates
            let placemarks = try await geocoder.geocodeAddressString(location)
            guard let coordinate = placemarks.first?.location?.coordinate else {
                return nil
            }

            // Fetch weather forecast using WeatherKit
            let weather = try await weatherService.weather(
                for: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                including: .daily
            )

            // Find the forecast for the event date
            let calendar = Calendar.current
            let eventDay = calendar.startOfDay(for: date)

            if let dayForecast = weather.first(where: { forecast in
                calendar.isDate(forecast.date, inSameDayAs: eventDay)
            }) {
                // Format weather description
                let temp = Int(dayForecast.highTemperature.converted(to: .fahrenheit).value)
                let condition = dayForecast.condition.description
                let symbol = weatherSymbol(for: dayForecast.condition)

                return "\(symbol) \(condition), \(temp)°F"
            }

            return nil
        } catch {
            print("⚠️ Weather fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func weatherSymbol(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear:
            return "☀️"
        case .partlyCloudy:
            return "⛅️"
        case .cloudy, .mostlyCloudy:
            return "☁️"
        case .rain, .drizzle, .heavyRain:
            return "🌧"
        case .snow, .sleet, .heavySnow:
            return "❄️"
        case .thunderstorms:
            return "⛈"
        case .windy, .breezy:
            return "💨"
        case .foggy, .haze:
            return "🌫"
        default:
            return "🌤"
        }
    }
}

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
    @StateObject private var googleCalendarManager = GoogleCalendarManager.shared
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
    @State private var lastBannerInteractionTime = Date()
    @State private var bannerInactivityTimer: Timer?
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var showingFilterSheet = false
    @State private var showingSearch = false
    @State private var showingExpandedHeader = false
    @State private var expandedCardId: String? = nil
    @State private var eventsLoadedGeneration = 0 // Increments when events first load
    @State private var quickAddDate: Date? = nil // For quick add from calendar tap

    // Memoized filtered events - computed only when dependencies change
    private var filteredEvents: [CalendarEvent] {
        let baseEvents: [CalendarEvent]

        if isMonthInPast(currentMonth) {
            // Past month: only show memories from that specific month
            baseEvents = viewModel.pastEvents.filter { event in
                Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
            }
        } else if isMonthInFuture(currentMonth) {
            // Future month: only show upcoming events from that specific month
            baseEvents = viewModel.upcomingEvents.filter { event in
                Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
            }
        } else {
            // Current month: filter both upcoming and memories to current month only
            if selectedTab == 0 {
                // Upcoming tab: filter to current month
                baseEvents = viewModel.upcomingEvents.filter { event in
                    Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
                }
            } else {
                // Memories tab: filter to current month
                baseEvents = viewModel.pastEvents.filter { event in
                    Calendar.current.isDate(event.date, equalTo: currentMonth, toGranularity: .month)
                }
            }
        }

        var filtered = baseEvents

        // Only filter by selected day if one is selected
        if let selectedDay = selectedDay {
            let calendar = Calendar.current
            filtered = filtered.filter { event in
                // Check if selected day is the start date
                if calendar.isDate(event.date, inSameDayAs: selectedDay) {
                    return true
                }
                // Check if selected day falls within multi-day event range
                if let endDate = event.endDate {
                    let startOfEventDay = calendar.startOfDay(for: event.date)
                    let startOfEndDay = calendar.startOfDay(for: endDate)
                    let startOfSelectedDay = calendar.startOfDay(for: selectedDay)
                    return startOfSelectedDay >= startOfEventDay && startOfSelectedDay <= startOfEndDay
                }
                return false
            }
        }

        // Filter by tags
        if !selectedTags.isEmpty {
            filtered = filtered.filter { event in
                guard let tags = event.tags else { return false }
                return !selectedTags.isDisjoint(with: tags)
            }
        }

        return filtered
    }

    // Get all unique tags from events
    private var allTags: [String] {
        let allEvents = viewModel.events
        let tags = allEvents.compactMap { $0.tags }.flatMap { $0 }
        return Array(Set(tags)).sorted()
    }

    // Helper computed property for upcoming events in current month
    private var next5UpcomingEvents: [CalendarEvent] {
        Array(viewModel.upcomingEvents.prefix(5))
    }

    @ViewBuilder
    private var upcomingEventsBanner: some View {
        if !next5UpcomingEvents.isEmpty {
            VStack(spacing: 0) {
                TabView(selection: $countdownBannerIndex) {
                    ForEach(Array(next5UpcomingEvents.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            Image(systemName: event.isSpecial ? "star.fill" : "calendar")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(dateRangeText(for: event))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text("•")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(countdownText(for: event))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.95))
                                }
                            }

                            Spacer()

                            if next5UpcomingEvents.count > 1 {
                                Text("\(index + 1)/\(next5UpcomingEvents.count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.5, blue: 0.8),
                                    Color(red: 0.7, green: 0.6, blue: 0.9)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        .onTapGesture {
                            selectedEventForDetail = event
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 60)
                .onChange(of: countdownBannerIndex) { oldValue, newValue in
                    // Reset inactivity timer when user swipes
                    resetBannerInactivityTimer()
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var backgroundGradient: some View {
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
    }

    @ViewBuilder
    private var eventsListSection: some View {
        if filteredEvents.isEmpty {
            EmptyStateView(isUpcoming: selectedTab == 0)
                .padding(.top, 60)
        } else {
            VStack(spacing: 12) {
                ForEach(filteredEvents) { event in
                    ModernEventCard(
                        event: event,
                        onTap: {
                            selectedEventForDetail = event
                            expandedCardId = nil
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
                        },
                        expandedCardId: $expandedCardId
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                do {
                                    try await viewModel.deleteEvent(event)
                                } catch {
                                    errorMessage = "Failed to delete event: \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Expandable Header (inline, hidden when collapsed)
    @ViewBuilder
    private var expandableHeader: some View {
        if showingExpandedHeader {
            VStack(spacing: 16) {
                // Quick actions row
                HStack(spacing: 12) {
                    // New Plan button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showingExpandedHeader = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingAddEvent = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                            Text("New Plan")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.7, green: 0.45, blue: 0.95),
                                    Color(red: 0.55, green: 0.35, blue: 0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                    }

                    // Search button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showingExpandedHeader = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingSearch = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.body)
                            Text("Search")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                        )
                    }
                }

                // Filter and Refresh row
                HStack(spacing: 12) {
                    // Filter button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showingExpandedHeader = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingFilterSheet = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.body)
                            Text("Filters")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                        )
                    }

                    // Refresh button
                    Button(action: {
                        Task {
                            await refreshCalendar()
                        }
                        withAnimation(.spring(response: 0.3)) {
                            showingExpandedHeader = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                            Text("Refresh")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.98, green: 0.96, blue: 1.0))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var calendarScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Expandable header (hidden when collapsed)
                expandableHeader

                // Upcoming Events Banner (persistent across all months)
                upcomingEventsBanner

                // Sync indicator
                if googleCalendarManager.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing with Google Calendar...")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Month indicator for calendar
                Text(currentMonth, format: .dateTime.month(.wide).year())
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Calendar Grid
                CalendarGridView(
                    currentMonth: currentMonth,
                    events: viewModel.events,
                    selectedDay: $selectedDay,
                    selectedTab: $selectedTab,
                    onQuickAdd: { date in
                        quickAddDate = date
                        showingAddEvent = true
                    }
                )
                .id("\(currentMonth.timeIntervalSince1970)-\(eventsLoadedGeneration)-\(selectedDay?.timeIntervalSince1970 ?? 0)")
                .padding(.horizontal)
                .padding(.bottom, 16)
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let horizontalAmount = value.translation.width

                            if horizontalAmount < -50 {
                                // Swipe left - next month
                                withAnimation(.spring(response: 0.3)) {
                                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                                }
                            } else if horizontalAmount > 50 {
                                // Swipe right - previous month
                                withAnimation(.spring(response: 0.3)) {
                                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                                }
                            }
                        }
                )

                // Month Summary Card (only for past months)
                if isMonthInPast(currentMonth) {
                    MonthSummaryCard(
                        month: currentMonth,
                        events: eventsForCurrentMonth(),
                        photos: viewModel.photos,
                        isExpanded: $summaryCardExpanded,
                        onPhotoTap: { photoURLs, index in
                            recapPhotoData = RecapPhotoData(photoURLs: photoURLs, initialIndex: index)
                        }
                    )
                    .id(currentMonth)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }

                // Custom Tab Selector (only show for current month)
                if !isMonthInPast(currentMonth) && !isMonthInFuture(currentMonth) {
                    ModernTabSelector(selectedTab: $selectedTab)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }

                // Filter indicator
                if let selectedDay = selectedDay {
                    FilterHeaderView(
                        selectedDay: selectedDay,
                        eventCount: filteredEvents.count,
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
                eventsListSection
            }
        }
        .refreshable {
            // Show the expanded header when user pulls down
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showingExpandedHeader = true
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            // Auto-hide header when scrolling down
            if showingExpandedHeader && newValue > 50 {
                withAnimation(.spring(response: 0.3)) {
                    showingExpandedHeader = false
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                calendarScrollContent
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(initialDate: quickAddDate ?? selectedDate) { event in
                    do {
                        try await viewModel.addEvent(event)
                        quickAddDate = nil // Reset after adding
                    } catch {
                        errorMessage = "Failed to add event: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
            .onChange(of: showingAddEvent) { _, newValue in
                if !newValue {
                    quickAddDate = nil // Reset when sheet is dismissed
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
            .sheet(isPresented: $showingFilterSheet) {
                FilterTagsView(allTags: allTags, selectedTags: $selectedTags)
            }
            .sheet(isPresented: $showingSearch) {
                SearchEventsView(
                    events: viewModel.events,
                    onEventTap: { event in
                        showingSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedEventForDetail = event
                        }
                    },
                    onEventDelete: { event in
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
            .onChange(of: viewModel.events.count) { oldValue, newValue in
                // Increment generation when events load to force calendar refresh
                if oldValue == 0 && newValue > 0 {
                    eventsLoadedGeneration += 1
                }
            }
            .task {
                // Fetch weather for existing events when view appears
                await viewModel.fetchWeatherForEvents()
            }
            .onAppear {
                // Start inactivity timer when view appears
                resetBannerInactivityTimer()
            }
            .onDisappear {
                // Clean up timer when view disappears
                bannerInactivityTimer?.invalidate()
            }
        }
        .navigationTitle("Our Plans 💜")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Helper Functions

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

    func isMonthInFuture(_ date: Date) -> Bool {
        let now = Date()
        let currentMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
        let selectedMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))!
        return selectedMonthStart > currentMonthStart
    }

    func countdownText(for event: CalendarEvent) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: event.date)

        if let days = components.day, let hours = components.hour, let minutes = components.minute {
            if days > 1 {
                // More than 1 day: show only days
                return "\(days)d"
            } else if days == 1 {
                // Exactly 1 day: show days only
                return "1d"
            } else if hours > 0 {
                // Less than 1 day: show hours and minutes
                return "\(hours)h \(minutes)m"
            } else {
                // Less than 1 hour: show minutes only
                return "\(minutes)m"
            }
        }
        return ""
    }

    func dateRangeText(for event: CalendarEvent) -> String {
        let formatter = DateFormatter()

        if event.isMultiDay, let endDate = event.endDate {
            let calendar = Calendar.current
            let sameMonth = calendar.isDate(event.date, equalTo: endDate, toGranularity: .month)
            let sameYear = calendar.isDate(event.date, equalTo: endDate, toGranularity: .year)

            if sameMonth {
                // Same month: "Dec 15 - 18"
                formatter.dateFormat = "MMM d"
                let startStr = formatter.string(from: event.date)
                formatter.dateFormat = "d"
                let endStr = formatter.string(from: endDate)
                return "\(startStr) - \(endStr)"
            } else if sameYear {
                // Different months, same year: "Dec 28 - Jan 3"
                formatter.dateFormat = "MMM d"
                let startStr = formatter.string(from: event.date)
                let endStr = formatter.string(from: endDate)
                return "\(startStr) - \(endStr)"
            } else {
                // Different years: "Dec 28 '24 - Jan 3 '25"
                formatter.dateFormat = "MMM d ''yy"
                let startStr = formatter.string(from: event.date)
                let endStr = formatter.string(from: endDate)
                return "\(startStr) - \(endStr)"
            }
        } else {
            // Single day event
            formatter.dateFormat = "MMM d"
            return formatter.string(from: event.date)
        }
    }

    func resetBannerInactivityTimer() {
        // Invalidate existing timer
        bannerInactivityTimer?.invalidate()

        // Start new timer that resets to first event after 1 minute of inactivity
        bannerInactivityTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                countdownBannerIndex = 0
            }
        }
    }

    func refreshCalendar() async {
        // Sync with Google Calendar if signed in
        if googleCalendarManager.isSignedIn {
            do {
                try await withTimeout(seconds: 30) {
                    try await googleCalendarManager.syncEvents()
                }
            } catch is TimeoutError {
                await MainActor.run {
                    errorMessage = "Google Calendar sync timed out. Please try again."
                    showError = true
                }
            } catch {
                // Only show error if it's not a cancellation
                if !Task.isCancelled {
                    await MainActor.run {
                        errorMessage = "Failed to sync with Google Calendar: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        }

        // Reload local events
        viewModel.loadEvents()

        // Fetch weather for events
        await viewModel.fetchWeatherForEvents()
    }
}

// MARK: - Modern Countdown Banner
struct ModernCountdownBanner: View {
    let event: CalendarEvent
    let onTap: () -> Void
    @State private var timeRemaining: String = ""

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Icon (smaller)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: event.isSpecial ? "star.fill" : "clock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

                // Single line: event name + countdown
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("•")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))

                    Text(timeRemaining)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Glassmorphism effect
                    RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            )
            .shadow(color: event.isSpecial ? Color.purple.opacity(0.25) : Color.black.opacity(0.08),
                    radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            updateCountdown()
            let timerId = "countdown_\(event.id ?? UUID().uuidString)"
            TimerManager.shared.schedule(id: timerId, interval: 60, repeats: true) {
                updateCountdown()
            }
        }
        .onDisappear {
            let timerId = "countdown_\(event.id ?? UUID().uuidString)"
            TimerManager.shared.invalidate(id: timerId)
        }
    }

    func updateCountdown() {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: event.date)

        if let days = components.day, let hours = components.hour, let minutes = components.minute {
            if days > 1 {
                // More than 1 day: show only days
                timeRemaining = "\(days)d"
            } else if days == 1 {
                // Exactly 1 day: show days only
                timeRemaining = "1d"
            } else if hours > 0 {
                // Less than 1 day: show hours and minutes
                timeRemaining = "\(hours)h \(minutes)m"
            } else {
                // Less than 1 hour: show minutes only
                timeRemaining = "\(minutes)m"
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
    @Binding var expandedCardId: String?

    private var isExpanded: Bool {
        expandedCardId == event.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MAIN CARD CONTENT (always visible)
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
                    }

                    // Time
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(event.date, format: .dateTime.hour().minute())
                            .font(.system(size: 14))
                    }
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                    // Hint text when collapsed
                    if !isExpanded {
                        Text("Tap for details")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            .italic()
                    }
                }

                Spacer()
            }
            .padding(20)

            // EXPANDED SECTION (show when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        // Description
                        if !event.description.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "text.alignleft")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    .frame(width: 20)

                                Text(event.description)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            }
                        }

                        // Location
                        if !event.location.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    .frame(width: 20)

                                Text(event.location)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            }
                        }

                        // Weather
                        if let weather = event.weatherForecast, !weather.isEmpty, event.date > Date() {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "cloud.sun.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    .frame(width: 20)

                                Text(weather)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            }
                        }

                        // Button to open full view
                        Button(action: {
                            onTap()
                        }) {
                            HStack {
                                Image(systemName: !event.photoURLs.isEmpty ? "photo.fill" : "arrow.up.right.square.fill")
                                    .font(.caption)
                                Text(!event.photoURLs.isEmpty ? "View Photos & Details" : "View Full Details")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.4, blue: 0.95),
                                        Color(red: 0.55, green: 0.3, blue: 0.85)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            // Toggle expansion state
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isExpanded {
                    // Collapse if already expanded
                    expandedCardId = nil
                } else {
                    // Expand if collapsed
                    expandedCardId = event.id
                }
            }
        }
        .id(event.id) // Ensure stable identity for lazy loading
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
    @State private var showingEditView = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isUploadingPhotos = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadedCount: Int = 0
    @State private var totalUploadCount: Int = 0
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

    var backgroundColors: [Color] {
        if event.isSpecial {
            return [Color(red: 0.98, green: 0.9, blue: 1.0), Color.white]
        } else {
            return [Color(red: 0.95, green: 0.9, blue: 1.0), Color.white]
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient

                ScrollView {
                    VStack(spacing: 24) {
                        dateDisplayCard
                        photosSection
                        eventDetailsSection
                        Spacer()
                    }
                    .padding(.top)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
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
                            let photoURLToDelete = currentEvent.photoURLs[indexToDelete]
                            var updatedPhotoURLs = currentEvent.photoURLs
                            updatedPhotoURLs.remove(at: indexToDelete)
                            Task {
                                // Delete the photo document from Firestore and Storage
                                // This ensures proper cross-tab synchronization
                                try? await FirebaseManager.shared.deletePhotoByURL(photoURLToDelete)

                                // Update the event with the new photoURLs array
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
            .sheet(isPresented: $showingEditView) {
                EditEventView(event: currentEvent) { updatedEvent in
                    Task {
                        do {
                            try await FirebaseManager.shared.updateEvent(updatedEvent)
                            await MainActor.run {
                                currentEvent = updatedEvent
                            }
                        } catch {
                            print("❌ Failed to update event: \(error)")
                        }
                    }
                }
            }
        }
    }

    var backgroundGradient: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    var dateDisplayCard: some View {
        ZStack {
            // Background (either custom image or gradient)
            if let backgroundURL = currentEvent.backgroundImageURL {
                AsyncImage(url: URL(string: backgroundURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(currentEvent.backgroundScale ?? 1.0)
                            .offset(
                                x: CGFloat(currentEvent.backgroundOffsetX ?? 0.0),
                                y: CGFloat(currentEvent.backgroundOffsetY ?? 0.0)
                            )
                    } else {
                        defaultGradientBackground(isSpecial: currentEvent.isSpecial)
                    }
                }
            } else {
                defaultGradientBackground(isSpecial: currentEvent.isSpecial)
            }

            // Date text overlay
            VStack(spacing: 8) {
                if currentEvent.isMultiDay, let endDate = currentEvent.endDate {
                    // Multi-day event: show date range
                    dateRangeView(startDate: currentEvent.date, endDate: endDate)
                } else {
                    // Single day event
                    Text(currentEvent.date, format: .dateTime.day())
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                    Text(currentEvent.date, format: .dateTime.month(.wide).year())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                    Text(currentEvent.date, format: .dateTime.weekday(.wide))
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                }
            }
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: currentEvent.isSpecial ? Color.purple.opacity(0.4) : Color.black.opacity(0.2),
                radius: 15, x: 0, y: 5)
        .padding(.horizontal)
    }

    var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                                Text("Photos 📸")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                Spacer()

                                // Add photos button for past events
                                if isPastEvent {
                                    PhotosPicker(selection: $photoPickerItems, matching: .images) {
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

                            // Upload progress bar
                            if isUploadingPhotos {
                                VStack(spacing: 8) {
                                    ProgressView(value: uploadProgress, total: 1.0)
                                        .tint(Color(red: 0.6, green: 0.4, blue: 0.85))

                                    Text("Uploading \(uploadedCount) of \(totalUploadCount) photos...")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if !currentEvent.photoURLs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(currentEvent.photoURLs.enumerated()), id: \.offset) { index, photoURL in
                                            ZStack(alignment: .topTrailing) {
                                                AsyncImage(url: URL(string: photoURL)) { phase in
                                                    if let image = phase.image {
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 250, height: 250)
                                                            .clipped()
                                                    } else {
                                                        Color.gray.opacity(0.2)
                                                            .frame(width: 250, height: 250)
                                                            .overlay(ProgressView())
                                                    }
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 15))
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
    }

    var eventDetailsSection: some View {
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

            // Weather (if available and event is upcoming)
            if let weather = event.weatherForecast, !weather.isEmpty, event.date > Date() {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Weather Forecast", systemImage: "cloud.sun.fill")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                    Text(weather)
                        .font(.body)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                }
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
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
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
                HStack(spacing: 16) {
                    Button {
                        showingEditView = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))
                    }

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
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

                // Load image from cache or download asynchronously
                let image: UIImage?
                if let cachedImage = ImageCache.shared.get(forKey: photoURL) {
                    image = cachedImage
                } else if let url = URL(string: photoURL) {
                    // Asynchronous network call - no UI blocking
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let downloadedImage = UIImage(data: data) {
                            ImageCache.shared.set(downloadedImage, forKey: photoURL)
                            image = downloadedImage
                        } else {
                            image = nil
                        }
                    } catch {
                        if !errorOccurred {
                            errorOccurred = true
                            await MainActor.run {
                                saveErrorMessage = "Failed to download photo: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                        continue
                    }
                } else {
                    image = nil
                }

                guard let imageToSave = image else { continue }

                // Save image to photo album
                await withCheckedContinuation { continuation in
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
                        continuation.resume()
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            Task { @MainActor in
                                saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                        continuation.resume()
                    }
                    imageSaver.writeToPhotoAlbum(image: imageToSave)
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

        await MainActor.run {
            isUploadingPhotos = true
            totalUploadCount = items.count
            uploadedCount = 0
            uploadProgress = 0.0
        }

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

                // Extract original capture date from EXIF metadata
                let capturedAt = extractCaptureDate(from: data)
                if let capturedAt = capturedAt {
                    print("🔵 [UPLOAD] Extracted capture date: \(capturedAt)")
                } else {
                    print("🔵 [UPLOAD] No EXIF capture date found")
                }

                // Resize and compress
                let resized = uiImage.resized(toMaxDimension: 1920)
                print("🔵 [UPLOAD] Resized to: \(resized.size)")

                guard let compressedData = resized.compressed(toMaxBytes: 1_000_000) else {
                    print("🔴 [UPLOAD ERROR] Failed to compress image \(index + 1)")
                    uploadErrors.append("Failed to compress image \(index + 1)")
                    continue
                }

                print("🔵 [UPLOAD] Compressed size: \(compressedData.count) bytes")
                print("🔵 [UPLOAD] Uploading to Firebase with event linkage...")

                // Upload photo with event linkage to photo gallery
                let photoURL = try await FirebaseManager.shared.uploadPhoto(
                    imageData: compressedData,
                    caption: "",
                    uploadedBy: UserIdentityManager.shared.currentUserName,
                    capturedAt: capturedAt,
                    eventId: currentEvent.id,
                    folderId: nil
                )
                print("🟢 [UPLOAD SUCCESS] Photo \(index + 1) uploaded and linked to event: \(photoURL)")
                newPhotoURLs.append(photoURL)

                // Update progress
                await MainActor.run {
                    uploadedCount = index + 1
                    uploadProgress = Double(uploadedCount) / Double(totalUploadCount)
                }

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

                // Send push notification for photos added to event
                NotificationManager.shared.notifyPhotosAdded(
                    count: newPhotoURLs.count,
                    location: currentEvent.title,
                    eventId: currentEvent.id
                )

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

    private func defaultGradientBackground(isSpecial: Bool) -> some View {
        LinearGradient(
            colors: isSpecial ?
                [Color(red: 0.8, green: 0.3, blue: 0.7), Color(red: 0.6, green: 0.2, blue: 0.9)] :
                [Color(red: 0.5, green: 0.3, blue: 0.8), Color(red: 0.4, green: 0.2, blue: 0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func dateRangeView(startDate: Date, endDate: Date) -> some View {
        let calendar = Calendar.current
        let sameMonth = calendar.isDate(startDate, equalTo: endDate, toGranularity: .month)
        let sameYear = calendar.isDate(startDate, equalTo: endDate, toGranularity: .year)

        if sameMonth {
            // Same month: "15 - 18"
            HStack(spacing: 8) {
                Text(startDate, format: .dateTime.day())
                    .font(.system(size: 48, weight: .bold))
                Text("-")
                    .font(.system(size: 36, weight: .medium))
                Text(endDate, format: .dateTime.day())
                    .font(.system(size: 48, weight: .bold))
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

            Text(startDate, format: .dateTime.month(.wide).year())
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        } else if sameYear {
            // Different months, same year: "Dec 28 - Jan 3"
            HStack(spacing: 8) {
                Text(startDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 28, weight: .bold))
                Text("-")
                    .font(.system(size: 24, weight: .medium))
                Text(endDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 28, weight: .bold))
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

            Text(startDate, format: .dateTime.year())
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        } else {
            // Different years: "Dec 28, 2024 - Jan 3, 2025"
            VStack(spacing: 4) {
                Text(startDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 20, weight: .bold))
                Text("-")
                    .font(.system(size: 16, weight: .medium))
                Text(endDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
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
    @State private var isMultiDay = false
    @State private var endDate: Date
    @State private var isSpecial = false
    @State private var isSaving = false
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var showingLocationSearch = false

    init(initialDate: Date, onSave: @escaping (CalendarEvent) async -> Void) {
        self.initialDate = initialDate
        self.onSave = onSave
        _date = State(initialValue: initialDate)
        _endDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: initialDate) ?? initialDate)
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
                    DatePicker(isMultiDay ? "Start Date" : "Date & Time", selection: $date)

                    Toggle("Multi-Day Event", isOn: $isMultiDay)
                        .tint(Color(red: 0.6, green: 0.4, blue: 0.85))

                    if isMultiDay {
                        DatePicker("End Date", selection: $endDate, in: date..., displayedComponents: .date)
                            .onChange(of: date) { _, newDate in
                                // Ensure end date is not before start date
                                if endDate < newDate {
                                    endDate = Calendar.current.date(byAdding: .day, value: 1, to: newDate) ?? newDate
                                }
                            }

                        // Show duration
                        let days = Calendar.current.dateComponents([.day], from: date, to: endDate).day ?? 0
                        Text("\(days + 1) day\(days > 0 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }

                    HStack {
                        TextField("Location (optional)", text: $location)
                        Button(action: {
                            showingLocationSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                    }
                }

                Section {
                    Toggle("Special Event 💜", isOn: $isSpecial)
                }

                Section("Tags") {
                    HStack {
                        TextField("Add tag", text: $newTag)
                        Button(action: {
                            let trimmedTag = newTag.trimmingCharacters(in: .whitespaces)
                            if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
                                tags.append(trimmedTag)
                                newTag = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Button(action: {
                                            tags.removeAll { $0 == tag }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingLocationSearch) {
                LocationSearchView(location: $location)
            }
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

        // Fetch weather if location is provided
        var weather: String? = nil
        if !location.isEmpty {
            weather = await WeatherService.shared.fetchWeatherForEvent(location: location, date: date)
        }

        let event = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            description: description,
            date: date,
            endDate: isMultiDay ? endDate : nil,
            location: location,
            createdBy: UserIdentityManager.shared.currentUserName,
            isSpecial: isSpecial,
            photoURLs: [],
            googleCalendarId: nil,
            lastSyncedAt: nil,
            backgroundImageURL: nil,
            backgroundOffsetX: nil,
            backgroundOffsetY: nil,
            backgroundScale: nil,
            tags: tags.isEmpty ? nil : tags,
            weatherForecast: weather
        )

        await onSave(event)
        isSaving = false
        dismiss()
    }
}

// MARK: - Edit Event View
struct EditEventView: View {
    @Environment(\.dismiss) var dismiss
    let event: CalendarEvent
    let onSave: (CalendarEvent) async -> Void

    @State private var title: String
    @State private var description: String
    @State private var location: String
    @State private var date: Date
    @State private var isMultiDay: Bool
    @State private var endDate: Date
    @State private var isSpecial: Bool
    @State private var isSaving = false
    @State private var backgroundImageItem: PhotosPickerItem?
    @State private var isUploadingBackground = false
    @State private var backgroundImageURL: String?
    @State private var backgroundOffsetX: Double
    @State private var backgroundOffsetY: Double
    @State private var backgroundScale: Double
    @State private var showingBackgroundPicker = false
    @State private var showingBackgroundError = false
    @State private var backgroundErrorMessage = ""
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var showingLocationSearch = false

    init(event: CalendarEvent, onSave: @escaping (CalendarEvent) async -> Void) {
        self.event = event
        self.onSave = onSave
        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description)
        _location = State(initialValue: event.location)
        _date = State(initialValue: event.date)
        _isMultiDay = State(initialValue: event.endDate != nil)
        _endDate = State(initialValue: event.endDate ?? Calendar.current.date(byAdding: .day, value: 1, to: event.date) ?? event.date)
        _isSpecial = State(initialValue: event.isSpecial)
        _backgroundImageURL = State(initialValue: event.backgroundImageURL)
        _backgroundOffsetX = State(initialValue: event.backgroundOffsetX ?? 0.0)
        _backgroundOffsetY = State(initialValue: event.backgroundOffsetY ?? 0.0)
        _backgroundScale = State(initialValue: event.backgroundScale ?? 1.0)
        _tags = State(initialValue: event.tags ?? [])
    }

    var body: some View {
        NavigationView {
            Form {
                detailsSection
                whenWhereSection
                specialEventSection
                tagsSection
                backgroundSection
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .photosPicker(isPresented: $showingBackgroundPicker, selection: $backgroundImageItem, matching: .images)
            .onChange(of: backgroundImageItem) { oldValue, newValue in
                Task {
                    await loadBackgroundImage()
                }
            }
            .alert("Background Upload Error", isPresented: $showingBackgroundError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backgroundErrorMessage)
            }
            .sheet(isPresented: $showingLocationSearch) {
                LocationSearchView(location: $location)
            }
        }
    }

    var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    var whenWhereSection: some View {
        Section("When & Where") {
            DatePicker(isMultiDay ? "Start Date" : "Date & Time", selection: $date)

            Toggle("Multi-Day Event", isOn: $isMultiDay)
                .tint(Color(red: 0.6, green: 0.4, blue: 0.85))

            if isMultiDay {
                DatePicker("End Date", selection: $endDate, in: date..., displayedComponents: .date)
                    .onChange(of: date) { _, newDate in
                        if endDate < newDate {
                            endDate = Calendar.current.date(byAdding: .day, value: 1, to: newDate) ?? newDate
                        }
                    }

                let days = Calendar.current.dateComponents([.day], from: date, to: endDate).day ?? 0
                Text("\(days + 1) day\(days > 0 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            }

            HStack {
                TextField("Location (optional)", text: $location)
                Button(action: {
                    showingLocationSearch = true
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
    }

    var specialEventSection: some View {
        Section {
            Toggle("Special Event 💜", isOn: $isSpecial)
        }
    }

    var tagsSection: some View {
        Section("Tags") {
            HStack {
                TextField("Add tag", text: $newTag)
                Button(action: {
                    let trimmedTag = newTag.trimmingCharacters(in: .whitespaces)
                    if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
                        tags.append(trimmedTag)
                        newTag = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Button(action: {
                                    tags.removeAll { $0 == tag }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.6, green: 0.4, blue: 0.85))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    var backgroundSection: some View {
        Section("Event Card Background") {
            backgroundPreview
            backgroundButtons

            if backgroundImageURL != nil {
                positioningControls
            }
        }
    }

    var backgroundPreview: some View {
        VStack(spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack {
                if let backgroundURL = backgroundImageURL {
                    AsyncImage(url: URL(string: backgroundURL)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(backgroundScale)
                                .offset(x: backgroundOffsetX, y: backgroundOffsetY)
                        } else {
                            defaultBackground
                        }
                    }
                } else {
                    defaultBackground
                }

                VStack(spacing: 4) {
                    Text(date, format: .dateTime.day())
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                    Text(date, format: .dateTime.month(.wide).year())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    var backgroundButtons: some View {
        Button(action: {
            showingBackgroundPicker = true
        }) {
            HStack {
                Image(systemName: backgroundImageURL == nil ? "photo.badge.plus" : "photo")
                Text(backgroundImageURL == nil ? "Add Background Image" : "Change Background Image")
            }
        }

        if backgroundImageURL != nil {
            Button(role: .destructive, action: {
                backgroundImageURL = nil
                backgroundOffsetX = 0
                backgroundOffsetY = 0
                backgroundScale = 1.0
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Remove Background Image")
                }
            }
        }
    }

    var positioningControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image Position")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Horizontal")
                        .font(.caption2)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $backgroundOffsetX, in: -100...100)
                    Text("\(Int(backgroundOffsetX))")
                        .font(.caption2)
                        .frame(width: 30)
                }

                HStack {
                    Text("Vertical")
                        .font(.caption2)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $backgroundOffsetY, in: -100...100)
                    Text("\(Int(backgroundOffsetY))")
                        .font(.caption2)
                        .frame(width: 30)
                }

                HStack {
                    Text("Scale")
                        .font(.caption2)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $backgroundScale, in: 0.5...3.0)
                    Text(String(format: "%.1f", backgroundScale))
                        .font(.caption2)
                        .frame(width: 30)
                }
            }

            Button("Reset Position") {
                withAnimation {
                    backgroundOffsetX = 0
                    backgroundOffsetY = 0
                    backgroundScale = 1.0
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if isSaving || isUploadingBackground {
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

    var defaultBackground: some View {
        LinearGradient(
            colors: isSpecial ?
                [Color(red: 0.8, green: 0.3, blue: 0.7), Color(red: 0.6, green: 0.2, blue: 0.9)] :
                [Color(red: 0.5, green: 0.3, blue: 0.8), Color(red: 0.4, green: 0.2, blue: 0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func loadBackgroundImage() async {
        guard let item = backgroundImageItem else { return }

        isUploadingBackground = true

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    isUploadingBackground = false
                    backgroundErrorMessage = "Failed to load image data. Please try a different image."
                    showingBackgroundError = true
                }
                return
            }

            // Upload to Firebase Storage
            let url = try await FirebaseManager.shared.uploadEventPhoto(imageData: data)
            await MainActor.run {
                backgroundImageURL = url
                print("✅ Background image uploaded: \(url)")
            }
        } catch {
            print("❌ Failed to upload background image: \(error)")
            await MainActor.run {
                backgroundErrorMessage = "Failed to upload background image: \(error.localizedDescription)"
                showingBackgroundError = true
            }
        }

        await MainActor.run {
            isUploadingBackground = false
        }
    }

    func saveEvent() async {
        isSaving = true

        // Fetch weather if location is provided and date is in the future
        var weather: String? = event.weatherForecast
        if !location.isEmpty && date > Date() {
            weather = await WeatherService.shared.fetchWeatherForEvent(location: location, date: date)
        }

        var updatedEvent = event
        updatedEvent.title = title
        updatedEvent.description = description
        updatedEvent.date = date
        updatedEvent.endDate = isMultiDay ? endDate : nil
        updatedEvent.location = location
        updatedEvent.isSpecial = isSpecial
        updatedEvent.backgroundImageURL = backgroundImageURL
        updatedEvent.backgroundOffsetX = backgroundOffsetX
        updatedEvent.backgroundOffsetY = backgroundOffsetY
        updatedEvent.backgroundScale = backgroundScale
        updatedEvent.tags = tags.isEmpty ? nil : tags
        updatedEvent.weatherForecast = weather

        await onSave(updatedEvent)
        isSaving = false
        dismiss()
    }
}

// MARK: - View Models
class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var photos: [Photo] = []

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
        loadPhotos()
    }

    func loadEvents() {
        Task {
            for try await events in firebaseManager.getCalendarEvents() {
                await MainActor.run {
                    self.events = events
                    // Sync to widget
                    WidgetDataManager.shared.syncEvents(events)
                }
            }
        }
    }

    func loadPhotos() {
        Task {
            for try await photos in firebaseManager.getPhotos() {
                await MainActor.run {
                    self.photos = photos
                }
            }
        }
    }

    func addEvent(_ event: CalendarEvent) async throws {
        try await firebaseManager.addCalendarEvent(event)

        // Send push notification
        NotificationManager.shared.notifyEventCreated(event: event)

        // Schedule local reminders for 1 day and 2 hours before
        NotificationManager.shared.scheduleEventReminders(for: event)
    }

    func updateEvent(_ event: CalendarEvent) async throws {
        try await firebaseManager.updateEvent(event)

        // Send push notification
        NotificationManager.shared.notifyEventEdited(event: event)

        // Reschedule local reminders in case date changed
        NotificationManager.shared.scheduleEventReminders(for: event)
    }

    func deleteEvent(_ event: CalendarEvent) async throws {
        try await firebaseManager.deleteCalendarEvent(event)
    }

    func fetchWeatherForEvents() async {
        // Fetch weather for upcoming events that have location but no weather cached
        let eventsNeedingWeather = upcomingEvents.filter { event in
            !event.location.isEmpty &&
            event.weatherForecast == nil &&
            event.date.timeIntervalSinceNow < 10 * 24 * 60 * 60 // Within 10 days
        }

        for event in eventsNeedingWeather {
            if let weather = await WeatherService.shared.fetchWeatherForEvent(location: event.location, date: event.date) {
                var updatedEvent = event
                updatedEvent.weatherForecast = weather
                try? await firebaseManager.updateEvent(updatedEvent)
            }
        }
    }
}

// MARK: - Calendar Grid View
struct CalendarGridView: View {
    let currentMonth: Date
    let events: [CalendarEvent]
    @Binding var selectedDay: Date?
    @Binding var selectedTab: Int
    var onQuickAdd: ((Date) -> Void)? = nil // Quick add callback
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
                        let isSelectedValue = selectedDay != nil && calendar.isDate(date, inSameDayAs: selectedDay!)
                        let dayNum = calendar.component(.day, from: date)
                        let hasEvents = !eventsForDay(date).isEmpty
                        let _ = hasEvents ? print("🟢 Creating CalendarDayCell - Day \(dayNum), isSelected: \(isSelectedValue), selectedDay: \(selectedDay.map { calendar.component(.day, from: $0) } ?? 0)") : ()

                        CalendarDayCell(
                            date: date,
                            events: eventsForDay(date),
                            isSelected: isSelectedValue,
                            isToday: calendar.isDateInToday(date),
                            onTap: {
                                handleDayTap(date: date)
                            },
                            onQuickAdd: {
                                onQuickAdd?(date)
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
            // Check if date is the start date
            if calendar.isDate(event.date, inSameDayAs: date) {
                return true
            }
            // Check if date falls within multi-day event range
            if let endDate = event.endDate {
                let startOfEventDay = calendar.startOfDay(for: event.date)
                let startOfEndDay = calendar.startOfDay(for: endDate)
                let startOfDate = calendar.startOfDay(for: date)
                return startOfDate >= startOfEventDay && startOfDate <= startOfEndDay
            }
            return false
        }
    }

    func handleDayTap(date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy HH:mm"
        let isPastDate = date < Date()

        print("🔵 handleDayTap called")
        print("   Date tapped: \(dateFormatter.string(from: date))")
        print("   Is past date: \(isPastDate)")
        print("   Current selectedDay: \(selectedDay.map { dateFormatter.string(from: $0) } ?? "nil")")
        print("   Current tab: \(selectedTab)")

        // Set selection immediately without animation to ensure state is updated
        if selectedDay != nil && calendar.isDate(date, inSameDayAs: selectedDay!) {
            print("   ❌ Deselecting (same day tapped)")
            selectedDay = nil // Deselect if tapping same day
        } else {
            print("   ✅ Setting selectedDay to: \(dateFormatter.string(from: date))")
            selectedDay = date

            print("   New selectedDay value: \(selectedDay.map { dateFormatter.string(from: $0) } ?? "nil")")

            // Auto-switch tabs based on date
            if isPastDate && selectedTab == 0 {
                // Switch to Memories tab for past dates
                print("   📱 Switching to Memories tab (animated)")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = 1
                }
            } else if !isPastDate && selectedTab == 1 {
                // Switch to Upcoming tab for future dates
                print("   📱 Switching to Upcoming tab (animated)")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = 0
                }
            } else {
                print("   📱 No tab switch needed")
            }
        }

        print("   Final selectedDay: \(selectedDay.map { dateFormatter.string(from: $0) } ?? "nil")")
        print("   Final tab: \(selectedTab)")
        print("🔵 handleDayTap completed")
    }
}

// MARK: - Calendar Day Cell
struct CalendarDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void
    var onQuickAdd: (() -> Void)? = nil // Quick add for empty days

    @State private var showTooltip = false
    @State private var showQuickAddPrompt = false

    var body: some View {
        let dayNum = Calendar.current.component(.day, from: date)
        let isPastDate = date < Date()
        let _ = print("🟡 CalendarDayCell body - Day \(dayNum), isPast: \(isPastDate), isSelected: \(isSelected), hasEvents: \(!events.isEmpty)")

        return Button(action: {
            if events.isEmpty {
                if onQuickAdd != nil && !isPastDate {
                    // Show "Add Event" prompt for empty future days
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showQuickAddPrompt = true
                    }
                    // Auto-dismiss after 3 seconds if not tapped
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation(.spring(response: 0.2)) {
                            showQuickAddPrompt = false
                        }
                    }
                } else {
                    // Show brief feedback for empty past days
                    withAnimation(.spring(response: 0.2)) {
                        showTooltip = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring(response: 0.2)) {
                            showTooltip = false
                        }
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
                    } else if showQuickAddPrompt {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15))
                    }
                }
            )
            .overlay(
                // Quick add prompt overlay - just plus icon
                Group {
                    if showQuickAddPrompt {
                        Button(action: {
                            withAnimation(.spring(response: 0.2)) {
                                showQuickAddPrompt = false
                            }
                            onQuickAdd?()
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                .shadow(color: Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.4), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .offset(y: -30)
                        .transition(.scale.combined(with: .opacity))
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
    let photos: [Photo] // All photos to filter from
    @Binding var isExpanded: Bool
    let onPhotoTap: ([String], Int) -> Void

    @State private var displayedPhotoURLs: [String] = []
    @State private var shuffleCount = 0
    @State private var lastShuffledPosition: Int? = nil
    @State private var animatingPosition: Int? = nil
    @State private var showingAllPhotos = false
    private let maxShuffles = 15 // Stop shuffling after 15 cycles (1 minute at 4s intervals)
    private var shuffleTimerId: String {
        "shuffle_\(month.timeIntervalSince1970)"
    }

    var eventCount: Int { events.count }
    var specialEventCount: Int { events.filter { $0.isSpecial }.count }

    // Filter photos to only those captured in this month
    var photosForMonth: [Photo] {
        let calendar = Calendar.current
        return photos.filter { photo in
            let captureDate = photo.capturedAt ?? photo.createdAt
            return calendar.isDate(captureDate, equalTo: month, toGranularity: .month)
        }
    }

    var photoCount: Int { photosForMonth.count }
    var allPhotoURLs: [String] {
        photosForMonth.map { $0.imageURL }
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
                                GeometryReader { geometry in
                                    AsyncImage(url: URL(string: photoURL)) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                .clipped()
                                        } else {
                                            Color.gray.opacity(0.2)
                                                .overlay(ProgressView())
                                        }
                                    }
                                }
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                            .rotation3DEffect(
                                .degrees(animatingPosition == index ? 180 : 0),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                            .scaleEffect(animatingPosition == index ? 0.95 : 1.0)
                            .id(photoURL) // For animation
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // Button to view all photos
                    Button(action: {
                        showingAllPhotos = true
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.caption)
                            Text("View All \(photoCount) Photos")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.7, green: 0.4, blue: 0.95),
                                    Color(red: 0.55, green: 0.3, blue: 0.85)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
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
                    TimerManager.shared.invalidate(id: shuffleTimerId)
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
        .sheet(isPresented: $showingAllPhotos) {
            MonthPhotosGridView(
                month: month,
                photoURLs: allPhotoURLs,
                onPhotoTap: onPhotoTap
            )
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

        shuffleCount = 0
        lastShuffledPosition = nil
        TimerManager.shared.schedule(id: shuffleTimerId, interval: 4.0, repeats: true) {
            shuffleRandomPhoto()
        }
    }

    func shuffleRandomPhoto() {
        guard allPhotoURLs.count > 4, displayedPhotoURLs.count == 4 else { return }

        // Stop shuffling after max count to prevent memory leak
        shuffleCount += 1
        if shuffleCount >= maxShuffles {
            TimerManager.shared.invalidate(id: shuffleTimerId)
            return
        }

        // Pick a random position to replace (0-3), but not the same as last time
        var randomPosition: Int
        if let lastPosition = lastShuffledPosition {
            // Ensure we don't shuffle the same position twice in a row
            let availablePositions = (0..<4).filter { $0 != lastPosition }
            randomPosition = availablePositions.randomElement() ?? Int.random(in: 0..<4)
        } else {
            randomPosition = Int.random(in: 0..<4)
        }

        // Get photos not currently displayed
        let availablePhotos = allPhotoURLs.filter { !displayedPhotoURLs.contains($0) }

        guard !availablePhotos.isEmpty else { return }

        // Pick a random photo from available ones
        let newPhoto = availablePhotos.randomElement()!

        // Trigger flip animation
        withAnimation(.easeInOut(duration: 0.3)) {
            animatingPosition = randomPosition
        }

        // Wait for halfway through animation, then change photo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            displayedPhotoURLs[randomPosition] = newPhoto
            lastShuffledPosition = randomPosition
        }

        // Complete animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                animatingPosition = nil
            }
        }
    }
}

// MARK: - Month Photos Grid View
struct MonthPhotosGridView: View {
    let month: Date
    let photoURLs: [String]
    let onPhotoTap: ([String], Int) -> Void
    @Environment(\.dismiss) var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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

                ScrollView {
                    VStack(spacing: 20) {
                        // Header info
                        VStack(spacing: 8) {
                            Text(month, format: .dateTime.month(.wide).year())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))

                            Text("\(photoURLs.count) Photos")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }
                        .padding(.top, 8)

                        // Photo grid
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, photoURL in
                                Button(action: {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onPhotoTap(photoURLs, index)
                                    }
                                }) {
                                    AsyncImage(url: URL(string: photoURL)) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 110, height: 110)
                                                .clipped()
                                        } else {
                                            Color.gray.opacity(0.2)
                                                .frame(width: 110, height: 110)
                                                .overlay(ProgressView())
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("All Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
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

// MARK: - Location Search View
struct LocationSearchView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var location: String
    @StateObject private var searchCompleter = LocationSearchCompleter()

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Search location", text: $searchCompleter.searchQuery)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }

                if !searchCompleter.results.isEmpty {
                    Section("Suggestions") {
                        ForEach(searchCompleter.results, id: \.self) { result in
                            Button(action: {
                                location = result.title + (result.subtitle.isEmpty ? "" : ", \(result.subtitle)")
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .foregroundColor(.primary)
                                        .fontWeight(.medium)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchCompleter.searchQuery) { oldValue, newValue in
                searchCompleter.search()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Location Search Completer
class LocationSearchCompleter: NSObject, ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search() {
        completer.queryFragment = searchQuery
    }
}

extension LocationSearchCompleter: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Location search error: \(error.localizedDescription)")
    }
}

// MARK: - Search Events View
struct SearchEventsView: View {
    @Environment(\.dismiss) var dismiss
    let events: [CalendarEvent]
    let onEventTap: (CalendarEvent) -> Void
    let onEventDelete: (CalendarEvent) -> Void

    @State private var searchText = ""

    private var searchResults: [CalendarEvent] {
        if searchText.isEmpty {
            return events.sorted { $0.date > $1.date }
        }

        return events.filter { event in
            event.title.localizedCaseInsensitiveContains(searchText) ||
            event.description.localizedCaseInsensitiveContains(searchText) ||
            event.location.localizedCaseInsensitiveContains(searchText) ||
            (event.tags?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            List {
                if searchResults.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.5))

                            Text(searchText.isEmpty ? "Start typing to search" : "No events found")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            if !searchText.isEmpty {
                                Text("Try searching by title, description, location, or tags")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(searchResults) { event in
                        Button(action: {
                            onEventTap(event)
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        Text(event.date, format: .dateTime.month().day().year())
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        if event.date > Date() {
                                            Text("Upcoming")
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.2))
                                                .foregroundColor(.blue)
                                                .cornerRadius(8)
                                        } else {
                                            Text("Memory")
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.purple.opacity(0.2))
                                                .foregroundColor(.purple)
                                                .cornerRadius(8)
                                        }

                                        if event.isSpecial {
                                            Image(systemName: "star.fill")
                                                .foregroundColor(Color(red: 0.7, green: 0.4, blue: 0.9))
                                                .font(.caption)
                                        }
                                    }
                                }

                                if !event.location.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.caption)
                                        Text(event.location)
                                            .font(.caption)
                                    }
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                }

                                if let tags = event.tags, !tags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(tags, id: \.self) { tag in
                                                Text(tag)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.2))
                                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onEventDelete(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all events...")
            .navigationTitle("Search Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Filter Tags View
struct FilterTagsView: View {
    @Environment(\.dismiss) var dismiss
    let allTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        NavigationView {
            List {
                if allTags.isEmpty {
                    Section {
                        Text("No tags available")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section("Filter by Tags") {
                        ForEach(allTags, id: \.self) { tag in
                            Button(action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }) {
                                HStack {
                                    Text(tag)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedTags.contains(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear All") {
                        selectedTags.removeAll()
                    }
                    .disabled(selectedTags.isEmpty)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


#Preview {
    CalendarView()
}
