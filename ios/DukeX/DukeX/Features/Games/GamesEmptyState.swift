import SwiftUI

struct GamesEmptyState: View {
    let importGames: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("No Games")
                .font(.headline)

            Button(action: importGames) {
                Label("Import Game", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
