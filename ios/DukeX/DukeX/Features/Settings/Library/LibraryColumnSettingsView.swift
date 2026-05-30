import SwiftUI

struct LibraryColumnSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
        Toggle(isOn: $store.xboxNostalgiaThemeEnabled) {
            Label("Xbox Nostalgia Theme", systemImage: "xbox.logo")
        }

        Text("Uses an original Xbox-inspired animated background and green accent across the app.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Toggle(isOn: $store.gameLibraryListViewEnabled) {
            Label("List View", systemImage: "list.bullet.rectangle")
        }

        VStack(alignment: .leading, spacing: 8) {
            Label("Portrait View", systemImage: "rectangle.portrait")
                .font(.subheadline.weight(.semibold))

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

            Picker("Landscape View Columns", selection: $store.landscapeGameLibraryColumnCount) {
                ForEach(GameLibraryColumnCount.landscapeOptions) { count in
                    Text(count.title).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        .disabled(store.gameLibraryListViewEnabled)
        .opacity(store.gameLibraryListViewEnabled ? 0.45 : 1)

        Text("Grid view defaults to 2 portrait columns and 3 landscape columns.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
