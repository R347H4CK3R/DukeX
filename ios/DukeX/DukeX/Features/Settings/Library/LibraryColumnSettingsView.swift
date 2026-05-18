import SwiftUI

struct LibraryColumnSettingsView: View {
    @ObservedObject var store: EmulatorFileStore

    var body: some View {
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

        Text("Portrait defaults to 2 columns. Landscape defaults to 3 columns.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
