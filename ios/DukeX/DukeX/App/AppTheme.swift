import SwiftUI
import UIKit

struct DukeXTheme: Equatable {
    static let xboxNostalgiaDefaultsKey = "DukeXXboxNostalgiaThemeEnabled"

    private static let standardAccentColor = Color(red: 0.0, green: 0.38, blue: 0.42)
    static let originalXboxGreen = Color(red: 0.33, green: 0.86, blue: 0.24)

    let xboxNostalgiaEnabled: Bool

    init(xboxNostalgiaEnabled: Bool = false) {
        self.xboxNostalgiaEnabled = xboxNostalgiaEnabled
    }

    var accentColor: Color {
        xboxNostalgiaEnabled ? Self.originalXboxGreen : Self.standardAccentColor
    }

    var screenBackground: Color {
        guard xboxNostalgiaEnabled else {
            return Color(uiColor: .systemGroupedBackground)
        }

        return Self.dynamicColor(
            light: UIColor(red: 0.915, green: 0.970, blue: 0.910, alpha: 1.0),
            dark: UIColor(red: 0.010, green: 0.025, blue: 0.014, alpha: 1.0)
        )
    }

    var surfaceColor: Color {
        guard xboxNostalgiaEnabled else {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }

        return Self.dynamicColor(
            light: UIColor(red: 0.945, green: 0.985, blue: 0.940, alpha: 0.78),
            dark: UIColor(red: 0.045, green: 0.090, blue: 0.052, alpha: 0.74)
        )
    }

    var elevatedSurfaceColor: Color {
        guard xboxNostalgiaEnabled else {
            return Color(uiColor: .tertiarySystemGroupedBackground)
        }

        return Self.dynamicColor(
            light: UIColor(red: 0.970, green: 0.995, blue: 0.965, alpha: 0.84),
            dark: UIColor(red: 0.060, green: 0.125, blue: 0.067, alpha: 0.78)
        )
    }

    var borderColor: Color {
        xboxNostalgiaEnabled ? Self.originalXboxGreen.opacity(0.24) : Color.primary.opacity(0.06)
    }

    static func xboxBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
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

    static func xboxDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.42, green: 1.00, blue: 0.46).opacity(0.26)
        }

        return Color(red: 0.10, green: 0.42, blue: 0.18).opacity(0.11)
    }

    static func xboxAccentDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.42, green: 1.00, blue: 0.46).opacity(0.34)
        }

        return Color(red: 0.22, green: 0.70, blue: 0.28).opacity(0.12)
    }

    static func xboxSecondaryDotColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.46, green: 1.00, blue: 0.52).opacity(0.14)
        }

        return Color(red: 0.12, green: 0.44, blue: 0.18).opacity(0.05)
    }

    static func xboxGlowColors(for colorScheme: ColorScheme) -> (topLeading: Color, accent: Color, bottom: Color) {
        (
            topLeading: Color(red: 0.20, green: 1.00, blue: 0.36)
                .opacity(colorScheme == .dark ? 0.16 : 0.12),
            accent: Color(red: 0.30, green: 0.95, blue: 0.34)
                .opacity(colorScheme == .dark ? 0.14 : 0.06),
            bottom: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10)
        )
    }

    static func applyUIKitAppearance(xboxNostalgiaEnabled: Bool) {
        let tintColor = xboxNostalgiaEnabled
            ? UIColor(red: 0.33, green: 0.86, blue: 0.24, alpha: 1.0)
            : UIColor(red: 0.0, green: 0.38, blue: 0.42, alpha: 1.0)

        UIWindow.appearance().tintColor = tintColor
        UITableView.appearance().backgroundColor = xboxNostalgiaEnabled ? .clear : nil
        UICollectionView.appearance().backgroundColor = xboxNostalgiaEnabled ? .clear : nil

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        let tabAppearance = UITabBarAppearance()
        if xboxNostalgiaEnabled {
            tabAppearance.configureWithTransparentBackground()
            tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            tabAppearance.backgroundColor = UIColor(red: 0.02, green: 0.08, blue: 0.03, alpha: 0.34)
            tabAppearance.shadowColor = UIColor(red: 0.33, green: 0.86, blue: 0.24, alpha: 0.16)
        } else {
            tabAppearance.configureWithDefaultBackground()
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
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
            if theme.xboxNostalgiaEnabled {
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
            .scrollContentBackground(theme.xboxNostalgiaEnabled ? .hidden : .visible)
            .background {
                DukeXThemedBackgroundView(dimming: theme.xboxNostalgiaEnabled ? dimming : 0)
            }
    }
}

private struct DukeXThemedListRowBackgroundModifier: ViewModifier {
    @Environment(\.dukeXTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.xboxNostalgiaEnabled {
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
