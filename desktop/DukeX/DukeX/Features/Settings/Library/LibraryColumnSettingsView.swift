import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
        Toggle(isOn: themeBinding(for: .xboxNostalgia)) {
            Label {
                Text("Xbox Nostalgia Theme")
            } icon: {
                RingedThemeGlyph {
                    XboxNostalgiaThemeGlyph()
                }
            }
        }

        Text("Uses an original Xbox-inspired animated background and green accent across the app.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Toggle(isOn: themeBinding(for: .whatTheBleem)) {
            Label {
                Text("What the Bleem Theme")
            } icon: {
                RingedThemeGlyph {
                    PlayStationThemeGlyph()
                }
            }
        }

        Text("Uses a Playstation-inspired animated background and blue accent for those who feel Xbox isn't enough.")
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
                        .frame(width: 18.4, height: 18.4)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }

        Text("Uses a Manic EMU-inspired animated background and a red accent across the app.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        if store.livingOriginalThemeUnlocked {
            Toggle(isOn: themeBinding(for: .livingOriginal)) {
                Label {
                    Text("Living Original Theme")
                } icon: {
                    RingedThemeGlyph {
                        XBLThemeGlyph()
                    }
                }
            }

            Text("Uses an OG XBL Team-inspired animated background and an orange accent across the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

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

private struct XboxNostalgiaThemeGlyph: View {
    var body: some View {
        Image("XboxNostalgiaThemeIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14.2, height: 13.25)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }
}

private struct PlayStationThemeGlyph: View {
    var body: some View {
        Image(systemName: "playstation.logo")
            .resizable()
            .scaledToFit()
            .frame(width: 13.8, height: 13.8)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }
}

private struct XBLThemeGlyph: View {
    var body: some View {
        Image("XBLCommunityIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 15.8, height: 15.8)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }
}

private struct SunflowerThemeGlyph: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 2.1, height: 9.2)
                .offset(y: 4.5)

            Ellipse()
                .fill(Color.accentColor)
                .frame(width: 6.6, height: 3.4)
                .rotationEffect(.degrees(-32))
                .offset(x: 3.8, y: 5.1)

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Ellipse()
                        .fill(Color.accentColor)
                        .frame(width: 2.9, height: 6.1)
                        .offset(y: -3.8)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                Circle()
                    .fill(.black)
                    .frame(width: 4.4, height: 4.4)
                    .blendMode(.destinationOut)
            }
            .frame(width: 12, height: 12)
            .offset(y: -3.5)
            .compositingGroup()
        }
        .frame(width: 18, height: 18)
        .offset(y: 0.7)
        .accessibilityHidden(true)
    }
}

struct LibraryColumnSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
        #if targetEnvironment(macCatalyst) || os(macOS)
        VStack(alignment: .leading, spacing: 8) {
            Label("Game Grid", systemImage: "square.grid.3x3")
                .font(.subheadline.weight(.semibold))

            Text("Choose how many games appear per row in the desktop game library.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Games Per Row", selection: $store.landscapeGameLibraryColumnCount) {
                ForEach(GameLibraryColumnCount.landscapeOptions) { count in
                    Text(count.gamesPerRowTitle).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        #else
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

        #endif
    }
}
