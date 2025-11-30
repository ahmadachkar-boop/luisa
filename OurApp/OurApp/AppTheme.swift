import SwiftUI

// MARK: - App Theme Design System
/// Centralized design system for consistent styling across the app

struct AppTheme {

    // MARK: - Colors
    struct Colors {
        // Primary accent color
        static let accent = Color(red: 0.6, green: 0.4, blue: 0.85)
        static let accentLight = Color(red: 0.7, green: 0.5, blue: 0.95)
        static let accentDark = Color(red: 0.5, green: 0.3, blue: 0.75)

        // Text colors (3 levels)
        static let textPrimary = Color(red: 0.25, green: 0.15, blue: 0.45)    // Darkest - titles, headers
        static let textSecondary = Color(red: 0.35, green: 0.25, blue: 0.55)  // Medium - body text
        static let textTertiary = Color(red: 0.5, green: 0.4, blue: 0.7)      // Light - labels, hints, placeholders

        // Background gradient colors
        static let backgroundTop = Color(red: 0.88, green: 0.88, blue: 1.0)
        static let backgroundMiddle = Color(red: 0.92, green: 0.92, blue: 1.0)
        static let backgroundBottom = Color(red: 0.96, green: 0.96, blue: 1.0)

        // Card and surface colors
        static let cardBackground = Color.white
        static let cardBackgroundSecondary = Color(red: 0.95, green: 0.92, blue: 1.0)
        static let cardBorder = Color(red: 0.85, green: 0.75, blue: 0.95)

        // Button colors
        static let buttonPrimaryStart = Color(red: 0.7, green: 0.45, blue: 0.95)
        static let buttonPrimaryEnd = Color(red: 0.55, green: 0.35, blue: 0.85)
        static let buttonSecondaryBackground = Color(red: 0.95, green: 0.92, blue: 1.0)
        static let buttonSecondaryText = Color(red: 0.5, green: 0.35, blue: 0.75)

        // Status colors
        static let success = Color(red: 0.3, green: 0.7, blue: 0.4)
        static let warning = Color(red: 0.9, green: 0.7, blue: 0.2)
        static let error = Color(red: 0.85, green: 0.35, blue: 0.35)

        // Icon colors
        static let iconPrimary = Color(red: 0.6, green: 0.4, blue: 0.85)
        static let iconSecondary = Color(red: 0.5, green: 0.4, blue: 0.7)
    }

    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8      // Thumbnails, tags, small elements
        static let medium: CGFloat = 12    // Buttons, inputs, list items
        static let large: CGFloat = 16     // Cards, sheets
        static let xlarge: CGFloat = 20    // Main containers, modals
    }

    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Shadows
    struct Shadows {
        static let small = Shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        static let medium = Shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        static let large = Shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        static let accent = Shadow(color: Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Background Gradient
extension AppTheme {
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Colors.backgroundTop,
                Colors.backgroundMiddle,
                Colors.backgroundBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Colors.buttonPrimaryStart,
                Colors.buttonPrimaryEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - View Modifiers

/// Standard card style modifier
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.CornerRadius.large
    var hasShadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(AppTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: hasShadow ? .black.opacity(0.08) : .clear,
                radius: hasShadow ? 8 : 0,
                x: 0,
                y: hasShadow ? 4 : 0
            )
    }
}

/// Secondary card style (light purple background)
struct SecondaryCardStyle: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.CornerRadius.large

    func body(content: Content) -> some View {
        content
            .background(AppTheme.Colors.cardBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Primary button style
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                AppTheme.primaryButtonGradient
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1.0) : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary button style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(AppTheme.Colors.buttonSecondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.buttonSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Icon button style (circular)
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var hasBackground: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.Colors.accent)
            .frame(width: size, height: size)
            .background(
                hasBackground ?
                Circle().fill(AppTheme.Colors.cardBackground) : nil
            )
            .shadow(
                color: hasBackground ? .black.opacity(0.1) : .clear,
                radius: hasBackground ? 4 : 0,
                x: 0,
                y: hasBackground ? 2 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard card styling
    func cardStyle(cornerRadius: CGFloat = AppTheme.CornerRadius.large, hasShadow: Bool = true) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, hasShadow: hasShadow))
    }

    /// Apply secondary card styling
    func secondaryCardStyle(cornerRadius: CGFloat = AppTheme.CornerRadius.large) -> some View {
        modifier(SecondaryCardStyle(cornerRadius: cornerRadius))
    }

    /// Apply app background gradient
    func appBackground() -> some View {
        self.background(AppTheme.backgroundGradient.ignoresSafeArea())
    }

    /// Apply standard shadow
    func standardShadow(_ style: AppTheme.Shadow = AppTheme.Shadows.medium) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Navigation Title Style
extension View {
    /// Standard navigation styling for all pages
    func standardNavigation(title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.Colors.backgroundTop.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Text Styles

extension Text {
    func titleStyle() -> Text {
        self
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(AppTheme.Colors.textPrimary)
    }

    func headlineStyle() -> Text {
        self
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.Colors.textPrimary)
    }

    func bodyStyle() -> Text {
        self
            .font(.body)
            .foregroundColor(AppTheme.Colors.textSecondary)
    }

    func captionStyle() -> Text {
        self
            .font(.caption)
            .foregroundColor(AppTheme.Colors.textTertiary)
    }

    func labelStyle() -> Text {
        self
            .font(.subheadline)
            .foregroundColor(AppTheme.Colors.textTertiary)
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Colors preview
            Text("Colors")
                .titleStyle()

            HStack(spacing: 10) {
                Circle().fill(AppTheme.Colors.accent).frame(width: 40, height: 40)
                Circle().fill(AppTheme.Colors.textPrimary).frame(width: 40, height: 40)
                Circle().fill(AppTheme.Colors.textSecondary).frame(width: 40, height: 40)
                Circle().fill(AppTheme.Colors.textTertiary).frame(width: 40, height: 40)
            }

            // Text styles preview
            Text("Title Style").titleStyle()
            Text("Headline Style").headlineStyle()
            Text("Body Style").bodyStyle()
            Text("Caption Style").captionStyle()

            // Buttons preview
            Button("Primary Button") {}
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)

            Button("Secondary Button") {}
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal)

            // Card preview
            VStack {
                Text("Card Example").headlineStyle()
                Text("This is a card with standard styling").bodyStyle()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .cardStyle()
            .padding(.horizontal)
        }
        .padding()
    }
    .appBackground()
}
