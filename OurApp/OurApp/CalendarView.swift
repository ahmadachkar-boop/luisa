import SwiftUI
import PhotosUI
import MapKit

// Wrapper to make Int work with .fullScreenCover(item:)
struct CalendarPhotoIndex: Identifiable {
    let id = UUID()
    let value: Int
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

                        // Countdown Banner
                        if let nextEvent = viewModel.upcomingEvents.first {
                            ModernCountdownBanner(event: nextEvent)
                                .padding(.horizontal)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                    // Custom Tab Selector
                    ModernTabSelector(selectedTab: $selectedTab)
                        .padding(.horizontal)
                        .padding(.bottom, 20)

                    // Events list
                    ScrollView(showsIndicators: false) {
                        let eventsToShow = selectedTab == 0 ? viewModel.upcomingEvents : viewModel.pastEvents

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
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

// MARK: - Modern Countdown Banner
struct ModernCountdownBanner: View {
    let event: CalendarEvent
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?

    var body: some View {
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

#Preview {
    CalendarView()
}
