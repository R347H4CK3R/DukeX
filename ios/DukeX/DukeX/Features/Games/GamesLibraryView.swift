import SwiftUI

struct GamesLibraryView: View {
    @EnvironmentObject private var store: EmulatorFileStore

    let runtimeState: EmulatorCoreRuntime.RunState
    let launchDashboard: () -> Void
    let launchGame: (LibraryFile) -> Void
    let importGames: () -> Void
    let addCover: (LibraryFile) -> Void
    let importConfig: (LibraryFile) -> Void
    let clearShaderCache: (LibraryFile) -> Void
    let requestRemoveGame: (LibraryFile) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(action: launchDashboard) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.grid.1x2")
                            .foregroundStyle(Color.accentColor)
                        Text("Launch Dashboard")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!store.systemFilesReady || !runtimeState.canLaunch)
                .opacity((store.systemFilesReady && runtimeState.canLaunch) ? 1 : 0.45)

                if store.games.isEmpty {
                    GamesEmptyState(importGames: importGames)
                } else {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                        ForEach(store.games) { game in
                            GameCoverTile(
                                game: game,
                                canLaunch: store.systemFilesReady && runtimeState.canLaunch,
                                launch: { launchGame(game) },
                                addCover: { addCover(game) },
                                importConfig: { importConfig(game) },
                                clearShaderCache: { clearShaderCache(game) },
                                requestRemoveGame: { requestRemoveGame(game) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: importGames) {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Import Game")
            }
        }
    }
}
