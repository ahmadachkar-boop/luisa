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

    // Badge text (Tomorrow, Today, In 3 days, etc.)
    var badgeText: String {
        let totalHours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0

        if totalHours < 0 {
            return "Passed"
        } else if totalHours < 24 {
            return "Today"
        } else if daysRemaining == 1 {
            return "Tomorrow"
        } else if daysRemaining <= 7 {
            return "This Week"
        } else {
            return "Upcoming"
        }
    }

    // Countdown number value
    var countdownValue: Int {
        let totalHours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0

        if totalHours < 24 {
            return max(0, totalHours)
        } else {
            return daysRemaining
        }
    }

    // Countdown unit (day, days, hour, hours)
    var countdownUnit: String {
        let totalHours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0

        if totalHours < 24 {
            return totalHours == 1 ? "hour" : "hours"
        } else {
            return daysRemaining == 1 ? "day" : "days"
        }
    }

    // Formatted date string (e.g., "Nov 28")
    var shortDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: eventDate)
    }

    // Full date string (e.g., "Friday, Nov 28")
    var fullDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: eventDate)
    }

    static var placeholder: CountdownEntry {
        CountdownEntry(
            date: Date(),
            eventTitle: "Date Night",
            eventDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
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

// MARK: - Decorative Circle View
struct DecorativeCircle: View {
    let size: CGFloat
    let opacity: Double
    let offsetX: CGFloat
    let offsetY: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(opacity))
            .frame(width: size, height: size)
            .offset(x: offsetX, y: offsetY)
    }
}

// MARK: - Small Widget View
struct CountdownWidgetSmallView: View {
    let entry: CountdownEntry

    var body: some View {
        if entry.isEmpty {
            emptyView
        } else {
            GeometryReader { geometry in
                ZStack {
                    // Decorative circles
                    DecorativeCircle(size: 96, opacity: 0.1, offsetX: geometry.size.width - 48, offsetY: -32)
                    DecorativeCircle(size: 64, opacity: 0.05, offsetX: -24, offsetY: geometry.size.height - 24)

                    // Content
                    VStack(alignment: .leading, spacing: 0) {
                        // Top section - Badge and Title
                        VStack(alignment: .leading, spacing: 6) {
                            // Badge
                            Text(entry.badgeText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())

                            // Event title
                            Text(entry.eventTitle)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        // Bottom section - Date and Countdown
                        HStack(alignment: .bottom) {
                            // Date
                            Text(entry.shortDateText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .textCase(.uppercase)

                            Spacer()

                            // Countdown
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(entry.countdownValue)")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.white)
                                Text(entry.countdownUnit)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .textCase(.uppercase)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.7))

            Text("No Plans Yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget View
struct CountdownWidgetMediumView: View {
    let entry: CountdownEntry

    var body: some View {
        if entry.isEmpty {
            emptyView
        } else {
            GeometryReader { geometry in
                ZStack {
                    // Decorative circles
                    DecorativeCircle(size: 128, opacity: 0.1, offsetX: geometry.size.width - 64, offsetY: -48)
                    DecorativeCircle(size: 80, opacity: 0.05, offsetX: geometry.size.width / 2, offsetY: geometry.size.height - 40)

                    // Content
                    VStack(alignment: .leading, spacing: 0) {
                        // Top section
                        HStack(alignment: .top) {
                            // Left - Badge, Title, Description
                            VStack(alignment: .leading, spacing: 6) {
                                // Badge
                                Text(entry.badgeText)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Capsule())

                                // Event title
                                Text(entry.eventTitle)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                // Location/Description
                                if !entry.location.isEmpty {
                                    Text(entry.location)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            // Right - Countdown
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(entry.countdownValue)")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("\(entry.countdownUnit) left")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .textCase(.uppercase)
                            }
                        }

                        Spacer()

                        // Bottom - Calendar date
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Text(entry.fullDateText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    var emptyView: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text("No Upcoming Plans")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Tap to add your next adventure!")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(20)
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
                    // Purple background matching the design (bg-purple-400 ~ #a855f7)
                    Color(red: 0.66, green: 0.33, blue: 0.97)
                }
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
