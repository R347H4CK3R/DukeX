import SwiftUI
import UIKit

enum DukeXThemeMode: String, CaseIterable, Identifiable {
    case standard
    case xboxNostalgia
    case manicFeelings
    case alwaysRemembered

    var id: String { rawValue }

    var usesAnimatedBackground: Bool {
        switch self {
        case .xboxNostalgia, .manicFeelings, .alwaysRemembered:
            return true
        case .standard:
            return false
        }
    }

    var usesThemedBackground: Bool {
        self != .standard
    }
}

struct DukeXTheme: Equatable {
    static let selectedThemeDefaultsKey = "DukeXSelectedThemeMode"
    static let xboxNostalgiaDefaultsKey = "DukeXXboxNostalgiaThemeEnabled"

    private static let standardAccentColor = Color(red: 0.0, green: 0.38, blue: 0.42)
    static let originalXboxGreen = Color(red: 0.33, green: 0.86, blue: 0.24)
    static let manicFeelingsRed = Color(red: 1.00, green: 0.05, blue: 0.20)
    static let alwaysRememberedLavender = Color(red: 0.64, green: 0.44, blue: 0.92)

    let mode: DukeXThemeMode

    init(mode: DukeXThemeMode = .standard) {
        self.mode = mode
    }

    init(xboxNostalgiaEnabled: Bool) {
        mode = xboxNostalgiaEnabled ? .xboxNostalgia : .standard
    }

    var xboxNostalgiaEnabled: Bool {
        mode == .xboxNostalgia
    }

    var manicFeelingsEnabled: Bool {
        mode == .manicFeelings
    }

    var alwaysRememberedEnabled: Bool {
        mode == .alwaysRemembered
    }

    var usesAnimatedBackground: Bool {
        mode.usesAnimatedBackground
    }

    var usesThemedBackground: Bool {
        mode.usesThemedBackground
    }

    var accentColor: Color {
        switch mode {
        case .standard:
            return Self.standardAccentColor
        case .xboxNostalgia:
            return Self.originalXboxGreen
        case .manicFeelings:
            return Self.manicFeelingsRed
        case .alwaysRemembered:
            return Self.alwaysRememberedLavender
        }
    }

    var screenBackground: Color {
        switch mode {
        case .standard:
            return Color(uiColor: .systemGroupedBackground)
        case .xboxNostalgia:
            return Self.dynamicColor(
                light: UIColor(red: 0.915, green: 0.970, blue: 0.910, alpha: 1.0),
                dark: UIColor(red: 0.010, green: 0.025, blue: 0.014, alpha: 1.0)
            )
        case .manicFeelings:
            return Self.dynamicColor(
                light: UIColor(red: 1.000, green: 0.945, blue: 0.955, alpha: 1.0),
                dark: UIColor(red: 0.050, green: 0.008, blue: 0.018, alpha: 1.0)
            )
        case .alwaysRemembered:
            return Self.dynamicColor(
                light: UIColor(red: 0.925, green: 0.880, blue: 1.000, alpha: 1.0),
                dark: UIColor(red: 0.135, green: 0.090, blue: 0.205, alpha: 1.0)
            )
        }
    }

    var surfaceColor: Color {
        switch mode {
        case .standard:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .xboxNostalgia:
            return Self.dynamicColor(
                light: UIColor(red: 0.945, green: 0.985, blue: 0.940, alpha: 0.78),
                dark: UIColor(red: 0.045, green: 0.090, blue: 0.052, alpha: 0.74)
            )
        case .manicFeelings:
            return Self.dynamicColor(
                light: UIColor(red: 1.000, green: 0.940, blue: 0.955, alpha: 0.78),
                dark: UIColor(red: 0.105, green: 0.018, blue: 0.036, alpha: 0.74)
            )
        case .alwaysRemembered:
            return Self.dynamicColor(
                light: UIColor(red: 0.965, green: 0.940, blue: 1.000, alpha: 0.80),
                dark: UIColor(red: 0.185, green: 0.125, blue: 0.275, alpha: 0.76)
            )
        }
    }

    var elevatedSurfaceColor: Color {
        switch mode {
        case .standard:
            return Color(uiColor: .tertiarySystemGroupedBackground)
        case .xboxNostalgia:
            return Self.dynamicColor(
                light: UIColor(red: 0.970, green: 0.995, blue: 0.965, alpha: 0.84),
                dark: UIColor(red: 0.060, green: 0.125, blue: 0.067, alpha: 0.78)
            )
        case .manicFeelings:
            return Self.dynamicColor(
                light: UIColor(red: 1.000, green: 0.965, blue: 0.972, alpha: 0.84),
                dark: UIColor(red: 0.135, green: 0.025, blue: 0.044, alpha: 0.78)
            )
        case .alwaysRemembered:
            return Self.dynamicColor(
                light: UIColor(red: 0.982, green: 0.965, blue: 1.000, alpha: 0.86),
                dark: UIColor(red: 0.225, green: 0.155, blue: 0.330, alpha: 0.80)
            )
        }
    }

    var borderColor: Color {
        switch mode {
        case .standard:
            return Color.primary.opacity(0.06)
        case .xboxNostalgia:
            return Self.originalXboxGreen.opacity(0.24)
        case .manicFeelings:
            return Self.manicFeelingsRed.opacity(0.26)
        case .alwaysRemembered:
            return Self.alwaysRememberedLavender.opacity(0.26)
        }
    }

    func animatedBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
        switch mode {
        case .manicFeelings:
            return Self.manicBackgroundColors(for: colorScheme)
        case .alwaysRemembered:
            return Self.alwaysRememberedBackgroundColors(for: colorScheme)
        case .standard, .xboxNostalgia:
            return Self.xboxBackgroundColors(for: colorScheme)
        }
    }

    func animatedDotColor(for colorScheme: ColorScheme) -> Color {
        switch mode {
        case .manicFeelings:
            return Self.manicDotColor(for: colorScheme)
        case .alwaysRemembered:
            return Self.alwaysRememberedDotColor(for: colorScheme)
        case .standard, .xboxNostalgia:
            return Self.xboxDotColor(for: colorScheme)
        }
    }

    func animatedAccentDotColor(for colorScheme: ColorScheme) -> Color {
        switch mode {
        case .manicFeelings:
            return Self.manicAccentDotColor(for: colorScheme)
        case .alwaysRemembered:
            return Self.alwaysRememberedAccentDotColor(for: colorScheme)
        case .standard, .xboxNostalgia:
            return Self.xboxAccentDotColor(for: colorScheme)
        }
    }

    func animatedSecondaryDotColor(for colorScheme: ColorScheme) -> Color {
        switch mode {
        case .manicFeelings:
            return Self.manicSecondaryDotColor(for: colorScheme)
        case .alwaysRemembered:
            return Self.alwaysRememberedSecondaryDotColor(for: colorScheme)
        case .standard, .xboxNostalgia:
            return Self.xboxSecondaryDotColor(for: colorScheme)
        }
    }

    func animatedGlowColors(for colorScheme: ColorScheme) -> (topLeading: Color, accent: Color, bottom: Color) {
        switch mode {
        case .manicFeelings:
            return Self.manicGlowColors(for: colorScheme)
        case .alwaysRemembered:
            return Self.alwaysRememberedGlowColors(for: colorScheme)
        case .standard, .xboxNostalgia:
            return Self.xboxGlowColors(for: colorScheme)
        }
    }

    private static func xboxBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.030, green: 0.080, blue: 0.045),
                Color(red: 0.012, green: 0.035, blue: 0.020),
                Color(red: 0.005, green: 0.012, blue: 0.006)
            ]
        }

        return [
            Color(red: 0.944, green: 0.986, blue: 0.944),
            Color(red: 0.904, green: 0.972, blue: 0.912),
            Color(red: 0.848, green: 0.940, blue: 0.875)
        ]
    }

    private static func manicBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.180, green: 0.018, blue: 0.042),
                Color(red: 0.095, green: 0.006, blue: 0.024),
                Color(red: 0.015, green: 0.000, blue: 0.005)
            ]
        }

        return [
            Color(red: 1.000, green: 0.392, blue: 0.494),
            Color(red: 1.000, green: 0.225, blue: 0.330),
            Color(red: 1.000, green: 0.020, blue: 0.180)
        ]
    }

    private static func alwaysRememberedBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.190, green: 0.130, blue: 0.285),
                Color(red: 0.130, green: 0.085, blue: 0.205),
                Color(red: 0.070, green: 0.045, blue: 0.115)
            ]
        }

        return [
            Color(red: 0.955, green: 0.925, blue: 1.000),
            Color(red: 0.925, green: 0.880, blue: 1.000),
            Color(red: 0.890, green: 0.835, blue: 0.985)
        ]
    }

    private static func xboxDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.42, green: 1.00, blue: 0.46).opacity(0.26)
        }

        return Color(red: 0.10, green: 0.42, blue: 0.18).opacity(0.11)
    }

    private static func manicDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 1.00, green: 0.38, blue: 0.50).opacity(0.24)
        }

        return Color(red: 0.40, green: 0.00, blue: 0.06).opacity(0.12)
    }

    private static func alwaysRememberedDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.78, green: 0.58, blue: 1.00).opacity(0.22)
        }

        return Color(red: 0.30, green: 0.14, blue: 0.48).opacity(0.10)
    }

    private static func xboxAccentDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.42, green: 1.00, blue: 0.46).opacity(0.34)
        }

        return Color(red: 0.22, green: 0.70, blue: 0.28).opacity(0.12)
    }

    private static func manicAccentDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 1.00, green: 0.48, blue: 0.58).opacity(0.32)
        }

        return Color.white.opacity(0.16)
    }

    private static func alwaysRememberedAccentDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.82, green: 0.62, blue: 1.00).opacity(0.30)
        }

        return Self.alwaysRememberedLavender.opacity(0.15)
    }

    private static func xboxSecondaryDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.46, green: 1.00, blue: 0.52).opacity(0.14)
        }

        return Color(red: 0.12, green: 0.44, blue: 0.18).opacity(0.05)
    }

    private static func manicSecondaryDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 1.00, green: 0.35, blue: 0.48).opacity(0.13)
        }

        return Color(red: 0.45, green: 0.00, blue: 0.08).opacity(0.05)
    }

    private static func alwaysRememberedSecondaryDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.76, green: 0.50, blue: 1.00).opacity(0.12)
        }

        return Color(red: 0.36, green: 0.18, blue: 0.52).opacity(0.05)
    }

    private static func xboxGlowColors(for colorScheme: ColorScheme) -> (topLeading: Color, accent: Color, bottom: Color) {
        (
            topLeading: Color(red: 0.20, green: 1.00, blue: 0.36)
                .opacity(colorScheme == .dark ? 0.16 : 0.12),
            accent: Color(red: 0.30, green: 0.95, blue: 0.34)
                .opacity(colorScheme == .dark ? 0.14 : 0.06),
            bottom: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10)
        )
    }

    private static func manicGlowColors(for colorScheme: ColorScheme) -> (topLeading: Color, accent: Color, bottom: Color) {
        (
            topLeading: Color(red: 1.00, green: 0.62, blue: 0.72)
                .opacity(colorScheme == .dark ? 0.18 : 0.16),
            accent: Color(red: 1.00, green: 0.04, blue: 0.20)
                .opacity(colorScheme == .dark ? 0.18 : 0.09),
            bottom: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14)
        )
    }

    private static func alwaysRememberedGlowColors(for colorScheme: ColorScheme) -> (topLeading: Color, accent: Color, bottom: Color) {
        (
            topLeading: Color(red: 0.82, green: 0.68, blue: 1.00)
                .opacity(colorScheme == .dark ? 0.18 : 0.15),
            accent: Self.alwaysRememberedLavender
                .opacity(colorScheme == .dark ? 0.18 : 0.09),
            bottom: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08)
        )
    }

    static func applyUIKitAppearance(themeMode: DukeXThemeMode) {
        let tintColor: UIColor
        switch themeMode {
        case .standard:
            tintColor = UIColor(red: 0.0, green: 0.38, blue: 0.42, alpha: 1.0)
        case .xboxNostalgia:
            tintColor = UIColor(red: 0.33, green: 0.86, blue: 0.24, alpha: 1.0)
        case .manicFeelings:
            tintColor = UIColor(red: 1.00, green: 0.05, blue: 0.20, alpha: 1.0)
        case .alwaysRemembered:
            tintColor = UIColor(red: 0.64, green: 0.44, blue: 0.92, alpha: 1.0)
        }

        UIWindow.appearance().tintColor = tintColor
        UITableView.appearance().backgroundColor = themeMode.usesThemedBackground ? .clear : nil
        UICollectionView.appearance().backgroundColor = themeMode.usesThemedBackground ? .clear : nil

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        let tabAppearance = UITabBarAppearance()
        if themeMode.usesAnimatedBackground {
            tabAppearance.configureWithTransparentBackground()
            tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            switch themeMode {
            case .standard:
                break
            case .xboxNostalgia:
                tabAppearance.backgroundColor = UIColor(red: 0.02, green: 0.08, blue: 0.03, alpha: 0.34)
                tabAppearance.shadowColor = UIColor(red: 0.33, green: 0.86, blue: 0.24, alpha: 0.16)
            case .manicFeelings:
                tabAppearance.backgroundColor = UIColor(red: 0.13, green: 0.01, blue: 0.03, alpha: 0.36)
                tabAppearance.shadowColor = UIColor(red: 1.00, green: 0.05, blue: 0.20, alpha: 0.18)
            case .alwaysRemembered:
                tabAppearance.backgroundColor = UIColor(red: 0.13, green: 0.08, blue: 0.22, alpha: 0.34)
                tabAppearance.shadowColor = UIColor(red: 0.64, green: 0.44, blue: 0.92, alpha: 0.18)
            }
        } else {
            tabAppearance.configureWithDefaultBackground()
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    static func applyUIKitAppearance(xboxNostalgiaEnabled: Bool) {
        applyUIKitAppearance(themeMode: xboxNostalgiaEnabled ? .xboxNostalgia : .standard)
    }

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct DukeXThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = DukeXTheme()
}

extension EnvironmentValues {
    var dukeXTheme: DukeXTheme {
        get { self[DukeXThemeEnvironmentKey.self] }
        set { self[DukeXThemeEnvironmentKey.self] = newValue }
    }
}

struct DukeXThemedBackgroundView: View {
    @Environment(\.dukeXTheme) private var theme

    let dimming: Double

    init(dimming: Double = 0) {
        self.dimming = dimming
    }

    var body: some View {
        ZStack {
            if theme.usesAnimatedBackground {
                NostalgicDotBackgroundView()
                if dimming > 0 {
                    Color.black.opacity(dimming)
                }
            } else {
                theme.screenBackground
            }
        }
        .ignoresSafeArea()
    }
}

private struct DukeXThemedListBackgroundModifier: ViewModifier {
    @Environment(\.dukeXTheme) private var theme
    let dimming: Double

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(theme.usesThemedBackground ? .hidden : .visible)
            .background {
                DukeXThemedBackgroundView(dimming: theme.usesAnimatedBackground ? dimming : 0)
            }
    }
}

private struct DukeXThemedListRowBackgroundModifier: ViewModifier {
    @Environment(\.dukeXTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.usesThemedBackground {
            content
                .listRowBackground(DukeXGlassListRowBackground())
                .listRowSeparatorTint(theme.borderColor)
        } else {
            content
        }
    }
}

private struct DukeXGlassListRowBackground: View {
    @Environment(\.dukeXTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                glassTint
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                theme.accentColor.opacity(colorScheme == .dark ? 0.045 : 0.075)
            }
    }

    private var glassTint: Color {
        if theme.manicFeelingsEnabled {
            if colorScheme == .dark {
                return Color(red: 0.095, green: 0.010, blue: 0.026).opacity(0.60)
            }

            return Color(red: 1.000, green: 0.920, blue: 0.940).opacity(0.46)
        }

        if theme.alwaysRememberedEnabled {
            if colorScheme == .dark {
                return Color(red: 0.140, green: 0.090, blue: 0.220).opacity(0.60)
            }

            return Color(red: 0.955, green: 0.925, blue: 1.000).opacity(0.48)
        }

        if colorScheme == .dark {
            return Color(red: 0.020, green: 0.070, blue: 0.035).opacity(0.58)
        }

        return Color(red: 0.935, green: 1.000, blue: 0.920).opacity(0.46)
    }
}

extension View {
    func dukeXThemedListBackground(dimming: Double = 0) -> some View {
        modifier(DukeXThemedListBackgroundModifier(dimming: dimming))
    }

    func dukeXThemedListRowBackground() -> some View {
        modifier(DukeXThemedListRowBackgroundModifier())
    }
}
