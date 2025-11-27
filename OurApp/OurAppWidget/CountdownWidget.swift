import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct CountdownEntry: TimelineEntry {
    let date: Date
    let eventTitle: String
    let eventDate: Date
    let isSpecial: Bool
    let location: String
    let isEmpty: Bool

    // Computed countdown properties
    var daysRemaining: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfEvent = calendar.startOfDay(for: eventDate)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfEvent).day ?? 0
    }

    var hoursRemaining: Int {
        let components = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate)
        return max(0, components.hour ?? 0)
    }

    var countdownText: String {
        if daysRemaining > 1 {
            return "\(daysRemaining) days"
        } else if daysRemaining == 1 {
            return "Tomorrow!"
        } else if daysRemaining == 0 {
            let hours = hoursRemaining
            if hours > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "Today!"
            }
        } else {
            return "Event passed"
        }
    }

    static var placeholder: CountdownEntry {
        CountdownEntry(
            date: Date(),
            eventTitle: "Date Night",
            eventDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
            isSpecial: true,
            location: "Our favorite spot",
            isEmpty: false
        )
    }

    static var empty: CountdownEntry {
        CountdownEntry(
            date: Date(),
            eventTitle: "No upcoming events",
            eventDate: Date(),
            isSpecial: false,
            location: "",
            isEmpty: true
        )
    }
}

// MARK: - Timeline Provider
struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        let entry = loadNextEvent() ?? .placeholder
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let entry = loadNextEvent() ?? .empty

        // Update timeline every hour, or at midnight for day changes
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let nextUpdate = min(nextHour, nextMidnight)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadNextEvent() -> CountdownEntry? {
        // Load from shared UserDefaults (App Group)
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.ourapp.shared"),
              let data = sharedDefaults.data(forKey: "upcomingEvents"),
              let events = try? JSONDecoder().decode([WidgetEvent].self, from: data),
              let nextEvent = events.first(where: { $0.date > Date() }) else {
            return nil
        }

        return CountdownEntry(
            date: Date(),
            eventTitle: nextEvent.title,
            eventDate: nextEvent.date,
            isSpecial: nextEvent.isSpecial,
            location: nextEvent.location,
            isEmpty: false
        )
    }
}

// MARK: - Widget Event Model (for shared data)
struct WidgetEvent: Codable {
    let id: String
    let title: String
    let date: Date
    let location: String
    let isSpecial: Bool
}

// MARK: - Widget Views

// Small Widget View
struct CountdownWidgetSmallView: View {
    let entry: CountdownEntry

    var body: some View {
        if entry.isEmpty {
            emptyView
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Countdown badge
                Text(entry.countdownText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Event title
                Text(entry.eventTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)

                Spacer()

                // Date
                Text(entry.eventDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: entry.isSpecial ?
                        [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.7, green: 0.25, blue: 0.6)] :
                        [Color(red: 0.6, green: 0.4, blue: 0.85), Color(red: 0.45, green: 0.3, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.7))

            Text("No Plans Yet")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.5, green: 0.4, blue: 0.7))
    }
}

// Medium Widget View
struct CountdownWidgetMediumView: View {
    let entry: CountdownEntry

    var body: some View {
        if entry.isEmpty {
            emptyView
        } else {
            HStack(spacing: 16) {
                // Left side - Countdown
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.countdownText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("until")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(minWidth: 80)

                // Right side - Event details
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if entry.isSpecial {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        Text(entry.eventTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Text(entry.eventDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))

                    if !entry.location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text(entry.location)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: entry.isSpecial ?
                        [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.7, green: 0.25, blue: 0.6)] :
                        [Color(red: 0.6, green: 0.4, blue: 0.85), Color(red: 0.45, green: 0.3, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    var emptyView: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text("No Upcoming Plans")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Tap to add your next adventure!")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.5, green: 0.4, blue: 0.7))
    }
}

// MARK: - Widget Entry View
struct CountdownWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CountdownEntry

    var body: some View {
        switch family {
        case .systemSmall:
            CountdownWidgetSmallView(entry: entry)
        case .systemMedium:
            CountdownWidgetMediumView(entry: entry)
        default:
            CountdownWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration
struct CountdownWidget: Widget {
    let kind: String = "CountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownProvider()) { entry in
            CountdownWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Event Countdown")
        .description("See your next upcoming plan at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle
@main
struct OurAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    CountdownWidget()
} timeline: {
    CountdownEntry.placeholder
}

#Preview(as: .systemMedium) {
    CountdownWidget()
} timeline: {
    CountdownEntry.placeholder
}
