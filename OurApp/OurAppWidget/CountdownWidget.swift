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
        let totalHours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0

        if totalHours < 0 {
            return "Event passed"
        } else if totalHours < 1 {
            // Less than 1 hour - show minutes
            let minutes = Calendar.current.dateComponents([.minute], from: Date(), to: eventDate).minute ?? 0
            if minutes > 0 {
                return "\(minutes) min"
            }
            return "Now!"
        } else if totalHours < 24 {
            // Less than 1 day - show hours
            return "\(totalHours) hour\(totalHours == 1 ? "" : "s")"
        } else if daysRemaining == 1 {
            return "Tomorrow!"
        } else {
            return "\(daysRemaining) days"
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

        // Update timeline every 15 minutes for more accurate countdowns
        let calendar = Calendar.current
        let next15Minutes = calendar.date(byAdding: .minute, value: 15, to: Date()) ?? Date()

        let timeline = Timeline(entries: [entry], policy: .after(next15Minutes))
        completion(timeline)
    }

    private func loadNextEvent() -> CountdownEntry? {
        // Load from shared UserDefaults (App Group)
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.ourapp"),
              let data = sharedDefaults.data(forKey: "upcomingEvents"),
              let events = try? JSONDecoder().decode([WidgetEvent].self, from: data),
              !events.isEmpty else {
            return nil
        }

        // Events are already filtered and sorted by the app, just get the first one
        guard let nextEvent = events.first else {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .containerBackground(for: .widget) {
                    widgetBackground(for: entry)
                }
        }
        .configurationDisplayName("Event Countdown")
        .description("See your next upcoming plan at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    @ViewBuilder
    private func widgetBackground(for entry: CountdownEntry) -> some View {
        if entry.isEmpty {
            Color(red: 0.5, green: 0.4, blue: 0.7)
        } else {
            LinearGradient(
                colors: entry.isSpecial ?
                    [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.7, green: 0.25, blue: 0.6)] :
                    [Color(red: 0.6, green: 0.4, blue: 0.85), Color(red: 0.45, green: 0.3, blue: 0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
