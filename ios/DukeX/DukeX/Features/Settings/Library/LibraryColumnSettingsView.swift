import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
        Toggle(isOn: themeBinding(for: .xboxNostalgia)) {
            Label("Xbox Nostalgia Theme", systemImage: "xbox.logo")
        }

        Text("Uses an original Xbox-inspired animated background and green accent across the app.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Toggle(isOn: themeBinding(for: .manicFeelings)) {
            Label {
                Text("Manic Feelings Theme")
            } icon: {
                RingedThemeGlyph {
                    Image("ManicFeelingsThemeIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }

        Text("Uses a Manic EMU-inspired animated background and a red accent across the app.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        if store.alwaysRememberedThemeUnlocked {
            Toggle(isOn: themeBinding(for: .alwaysRemembered)) {
                Label {
                    Text("Always Remembered Theme")
                } icon: {
                    RingedThemeGlyph {
                        SunflowerThemeGlyph()
                    }
                }
            }

            Text("Uses a special theme for those who took a moment to remember Lily. Thank you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func themeBinding(for mode: DukeXThemeMode) -> Binding<Bool> {
        Binding(
            get: { store.themeMode == mode },
            set: { store.setTheme(mode, enabled: $0) }
        )
    }
}

private struct RingedThemeGlyph<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor, lineWidth: 1.35)
                .frame(width: 22, height: 22)

            content
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

private struct SunflowerThemeGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Ellipse()
                    .fill(Color.accentColor)
                    .frame(width: 3.8, height: 8.4)
                    .offset(y: -5.2)
                    .rotationEffect(.degrees(Double(index) * 30))
            }

            Circle()
                .fill(.black)
                .frame(width: 6, height: 6)
                .blendMode(.destinationOut)
        }
        .frame(width: 17, height: 17)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

struct LibraryColumnSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
        Toggle(isOn: $store.gameLibraryListViewEnabled) {
            Label("List View", systemImage: "list.bullet.rectangle")
        }

        Text("List view presents the game library as rows. Game details and summaries can be added by long-pressing a game in List View and choosing \"Add Game Data\".")
            .font(.footnote)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 8) {
            Label("Portrait View", systemImage: "rectangle.portrait")
                .font(.subheadline.weight(.semibold))

            Text("Grid view defaults to two columns of games in portrait orientation.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Portrait View Columns", selection: $store.portraitGameLibraryColumnCount) {
                ForEach(GameLibraryColumnCount.portraitOptions) { count in
                    Text(count.title).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        .disabled(store.gameLibraryListViewEnabled)
        .opacity(store.gameLibraryListViewEnabled ? 0.45 : 1)

        VStack(alignment: .leading, spacing: 8) {
            Label("Landscape View", systemImage: "rectangle")
                .font(.subheadline.weight(.semibold))

            Text("Grid view defaults to three columns of games in landscape orientation.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Landscape View Columns", selection: $store.landscapeGameLibraryColumnCount) {
                ForEach(GameLibraryColumnCount.landscapeOptions) { count in
                    Text(count.title).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        .disabled(store.gameLibraryListViewEnabled)
        .opacity(store.gameLibraryListViewEnabled ? 0.45 : 1)

    }
}
