import SwiftUI

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showingAddEvent = false
    @State private var selectedDate = Date()
    @State private var selectedEventForDetail: CalendarEvent?

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.9, blue: 1.0),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Month view - fixed height to prevent expansion
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color(red: 0.5, green: 0.3, blue: 0.8))
                        .colorScheme(.light)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(15)
                        .padding()
                        .frame(height: 400)
                        .fixedSize(horizontal: false, vertical: true)

                    // Upcoming events
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upcoming Plans")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            .padding(.horizontal)

                        if viewModel.upcomingEvents.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

                                Text("No plans yet")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                Text("Add your first date! 💕")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                Text("Every moment together is special")
                                    .font(.caption2)
                                    .italic()
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.upcomingEvents) { event in
                                        EventCard(
                                            event: event,
                                            onTap: {
                                                selectedEventForDetail = event
                                            },
                                            onDelete: {
                                                Task {
                                                    await viewModel.deleteEvent(event)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("Our Plans 💕")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddEvent = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(initialDate: selectedDate) { event in
                    await viewModel.addEvent(event)
                }
            }
            .sheet(item: $selectedEventForDetail) { event in
                EventDetailView(event: event, onDelete: {
                    Task {
                        await viewModel.deleteEvent(event)
                        selectedEventForDetail = nil
                    }
                })
            }
        }
    }
}

struct EventCard: View {
    let event: CalendarEvent
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
        HStack(alignment: .top, spacing: 15) {
            // Cute date bubble
            VStack(spacing: 2) {
                Text(event.date, format: .dateTime.day())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(event.date, format: .dateTime.month(.abbreviated))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.95))
            }
            .frame(width: 65, height: 65)
            .background(
                LinearGradient(
                    colors: event.isSpecial ?
                        [Color(red: 0.8, green: 0.3, blue: 0.7), Color(red: 0.6, green: 0.2, blue: 0.9)] :
                        [Color(red: 0.5, green: 0.3, blue: 0.8), Color(red: 0.4, green: 0.2, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(15)
            .shadow(color: event.isSpecial ? Color.purple.opacity(0.4) : Color.black.opacity(0.15),
                    radius: event.isSpecial ? 8 : 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))

                    if event.isSpecial {
                        HStack(spacing: 2) {
                            Text("✨")
                            Text("💜")
                            Text("✨")
                        }
                        .font(.caption)
                    }
                }

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.35, green: 0.25, blue: 0.55))
                        .lineLimit(2)
                }

                if !event.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                        Text(event.location)
                            .font(.caption)
                    }
                    .foregroundColor(Color(red: 0.5, green: 0.3, blue: 0.7))
                    .padding(.top, 2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                    Text(event.createdBy)
                        .font(.caption2)
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                .padding(.top, 2)
            }

            Spacer()

            Button(action: {
                showingDeleteAlert = true
            }) {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: event.isSpecial ?
                        [Color.white, Color(red: 0.98, green: 0.95, blue: 1.0)] :
                        [Color.white, Color(red: 0.99, green: 0.97, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Special event glow
                if event.isSpecial {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            }
        )
        .cornerRadius(18)
        .shadow(color: event.isSpecial ? Color.purple.opacity(0.2) : Color.black.opacity(0.08),
                radius: event.isSpecial ? 12 : 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .alert("Delete Event?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove '\(event.title)' from your plans")
        }
    }
}

struct AddEventView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var date: Date
    @State private var isSpecial = false

    let onSave: (CalendarEvent) async -> Void

    init(initialDate: Date, onSave: @escaping (CalendarEvent) async -> Void) {
        _date = State(initialValue: initialDate)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title (e.g., 'Dinner Date')", text: $title)
                        .font(.body)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)

                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                        TextField("Location", text: $location)
                    }
                } header: {
                    Text("Event Details 💕")
                }

                Section {
                    DatePicker("Date", selection: $date)
                        .tint(Color(red: 0.6, green: 0.4, blue: 0.8))
                } header: {
                    Text("When? ⏰")
                }

                Section {
                    Toggle(isOn: $isSpecial) {
                        HStack {
                            Text("Special Event")
                            Text("✨💜✨")
                                .font(.caption)
                        }
                    }
                    .tint(Color(red: 0.7, green: 0.4, blue: 0.9))
                } header: {
                    Text("Make it memorable")
                }
            }
            .navigationTitle("Plan Something Special")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            let event = CalendarEvent(
                                title: title,
                                description: description,
                                date: date,
                                location: location,
                                createdBy: "You",
                                isSpecial: isSpecial
                            )
                            await onSave(event)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Save")
                            Text("💕")
                                .font(.caption)
                        }
                        .foregroundColor(title.isEmpty ? .gray : Color(red: 0.6, green: 0.3, blue: 0.8))
                        .fontWeight(.semibold)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct EventDetailView: View {
    let event: CalendarEvent
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteAlert = false

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

                                    Text(event.location)
                                        .font(.body)
                                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
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
            .alert("Delete Event?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will remove '\(event.title)' from your plans")
            }
        }
    }
}

class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []

    private let firebaseManager = FirebaseManager.shared

    var upcomingEvents: [CalendarEvent] {
        events.filter { $0.date >= Date() }
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

    func addEvent(_ event: CalendarEvent) async {
        do {
            try await firebaseManager.addCalendarEvent(event)
        } catch {
            print("Error adding event: \(error)")
        }
    }

    func deleteEvent(_ event: CalendarEvent) async {
        do {
            try await firebaseManager.deleteCalendarEvent(event)
        } catch {
            print("Error deleting event: \(error)")
        }
    }
}

#Preview {
    CalendarView()
}
