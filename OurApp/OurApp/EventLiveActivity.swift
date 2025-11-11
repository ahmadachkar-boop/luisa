import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Event Live Activity Widget
@available(iOS 16.1, *)
struct EventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            // Lock screen / banner UI
            HStack(spacing: 12) {
                // Left side: Event icon and name
                HStack(spacing: 8) {
                    Image(systemName: context.state.isSpecial ? "star.fill" : "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(context.state.eventTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Right side: Countdown
                Text(context.state.countdown)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded state (when long-pressed)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isSpecial ? "star.fill" : "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.eventTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            if context.state.totalEvents > 1 {
                                Text("Event \(context.state.currentIndex + 1) of \(context.state.totalEvents)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.countdown)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text(context.state.eventDate, style: .date)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.currentIndex > 0 {
                            Button(intent: PreviousEventIntent()) {
                                Label("Previous", systemImage: "chevron.left")
                                    .font(.caption)
                            }
                            .tint(.white.opacity(0.8))
                        }

                        Spacer()

                        if context.state.currentIndex < context.state.totalEvents - 1 {
                            Button(intent: NextEventIntent()) {
                                Label("Next", systemImage: "chevron.right")
                                    .font(.caption)
                            }
                            .tint(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal)
                }

            } compactLeading: {
                // Compact state - left side
                Image(systemName: context.state.isSpecial ? "star.fill" : "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

            } compactTrailing: {
                // Compact state - right side
                Text(context.state.countdown)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: 60)

            } minimal: {
                // Minimal state (when multiple activities)
                Image(systemName: context.state.isSpecial ? "star.fill" : "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - App Intents for Interactive Controls
@available(iOS 16.1, *)
struct PreviousEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Event"

    func perform() async throws -> some IntentResult {
        // This will be handled by your app
        return .result()
    }
}

@available(iOS 16.1, *)
struct NextEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Event"

    func perform() async throws -> some IntentResult {
        // This will be handled by your app
        return .result()
    }
}
