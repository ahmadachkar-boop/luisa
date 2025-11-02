import SwiftUI

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showingAddEvent = false
    @State private var selectedDate = Date()

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

                VStack {
                    // Month view
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color(red: 0.8, green: 0.7, blue: 1.0))
                        .padding()
                        .background(Color.white)
                        .cornerRadius(15)
                        .padding()

                    // Upcoming events
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upcoming Plans")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        if viewModel.upcomingEvents.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray)

                                Text("No plans yet")
                                    .foregroundColor(.gray)

                                Text("Add your first date! 💕")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.upcomingEvents) { event in
                                        EventCard(
                                            event: event,
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
                AddEventView { event in
                    await viewModel.addEvent(event)
                }
            }
        }
    }
}

struct EventCard: View {
    let event: CalendarEvent
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack {
                Text(event.date, format: .dateTime.day())
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))

                Text(event.date, format: .dateTime.month(.abbreviated))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)

                    if event.isSpecial {
                        Text("💜")
                    }
                }

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !event.location.isEmpty {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                        Text(event.location)
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                }

                Text("Added by \(event.createdBy)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: {
                showingDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .alert("Delete Event?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

struct AddEventView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var date = Date()
    @State private var isSpecial = false

    let onSave: (CalendarEvent) async -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Title (e.g., 'Dinner Date')", text: $title)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Location", text: $location)
                }

                Section("Date & Time") {
                    DatePicker("Date", selection: $date)
                }

                Section {
                    Toggle("Special Event 💜", isOn: $isSpecial)
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
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
                    }
                    .disabled(title.isEmpty)
                }
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
