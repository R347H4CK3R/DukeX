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

private struct GameCoverTile: View {
    let game: LibraryFile
    let canLaunch: Bool
    let launch: () -> Void
    let addCover: () -> Void
    let importConfig: () -> Void
    let clearShaderCache: () -> Void
    let requestRemoveGame: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: launch) {
                cover
                    .aspectRatio(0.70, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)

            Button(action: launch) {
                Text(game.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .top)
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .opacity(canLaunch ? 1 : 0.55)
        .contextMenu {
            Button(action: addCover) {
                Label("Add Cover", systemImage: "photo")
            }

            Button(action: importConfig) {
                Label(game.customConfigURL == nil ? "Import Config" : "Replace Config",
                      systemImage: "gearshape")
            }

            Button(action: clearShaderCache) {
                Label("Clear Shader Cache", systemImage: "xmark.bin")
            }

            Button(action: launch) {
                Label("Launch Game", systemImage: "play.circle")
            }
            .disabled(!canLaunch)

            Button(role: .destructive, action: requestRemoveGame) {
                Label("Remove Game", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURL = game.coverURL,
           let image = UIImage(contentsOfFile: coverURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))

                VStack(spacing: 10) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 42, weight: .regular))
                    Text(game.fallbackDisplayName)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GamesEmptyState: View {
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
