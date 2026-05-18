import SwiftUI

struct GameSortPicker: View {
    @Binding var selection: GameLibrarySortMode

    var body: some View {
        Picker("Sort Games", selection: $selection) {
            ForEach(GameLibrarySortMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .frame(height: GameLibraryGridMetrics.compactControlHeight)
        .pickerStyle(.segmented)
        .accessibilityLabel("Sort Games")
    }
}
