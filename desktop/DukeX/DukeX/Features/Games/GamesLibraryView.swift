import SwiftUI
import UIKit

struct GamesLibraryView: View {
    @Environment(\.dukeXTheme) private var theme
    @EnvironmentObject private var store: EmulatorFileStore
    @AppStorage(GameLibrarySortMode.defaultsKey) private var sortModeRawValue = GameLibrarySortMode.title.rawValue
    @State private var favoriteGameKeys = GameLibraryFavorites.load()
    @State private var recentlyPlayedGameTimes = GameLibraryRecents.load()

    let runtimeState: EmulatorCoreRuntime.RunState
    let liveStatusStore: InsigniaLiveStatusStore
    let metadataStore: GameMetadataStore
    let launchDashboard: () -> Void
    let launchGame: (LibraryFile) -> Void
    let importGames: () -> Void
    let addCover: (LibraryFile) -> Void
    let copyLaunchLink: (LibraryFile) -> Void
    let importConfig: (LibraryFile) -> Void
    let clearShaderCache: (LibraryFile) -> Void
    let editGameData: (LibraryFile) -> Void
    let requestRemoveGame: (LibraryFile) -> Void
    let launchManicEmu: (() -> Void)?
    let openXBLive: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let displayedGames = sortedGames
            standardLibraryContent(displayedGames: displayedGames, size: geometry.size)
            .background(Color.clear)
        }
        .background {
            DukeXThemedBackgroundView()
        }
        .toolbar {
            #if !targetEnvironment(macCatalyst)
            ToolbarItem(placement: .topBarLeading) {
                Button(action: importGames) {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Import Game")
            }

            ToolbarItem(placement: .topBarTrailing) {
                if let launchManicEmu {
                    Button(action: launchManicEmu) {
                        Image("ManicFeelingsThemeIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Open Manic EMU")
                } else if let openXBLive {
                    Button(action: openXBLive) {
                        Image("XBLCommunityIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Open xb.live")
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func standardLibraryContent(displayedGames: [LibraryFile], size: CGSize) -> some View {
        ScrollView {
            ZStack(alignment: .top) {
                libraryBackgroundContextMenu
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: size.height)

                VStack(spacing: 16) {
                    GameSortPicker(selection: sortModeBinding)

                    Button(action: launchDashboard) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.grid.1x2")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("Launch Dashboard")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: GameLibraryGridMetrics.compactControlHeight)
                        .padding(.horizontal, 12)
                        .background(theme.surfaceColor,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.borderColor, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.systemFilesReady || !runtimeState.canLaunch)
                    .opacity((store.systemFilesReady && runtimeState.canLaunch) ? 1 : 0.45)

                    if store.games.isEmpty {
                        GamesEmptyState(importGames: importGames)
                    } else if displayedGames.isEmpty {
                        GameLibraryFilterEmptyState(title: emptyFilterTitle, systemImage: emptyFilterSystemImage)
                    } else if gameLibraryListViewEnabled {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedGames) { game in
                                GameListRow(
                                    game: game,
                                    metadata: metadataStore.metadata(for: game),
                                    recentlyPlayedTime: recentlyPlayedTime(for: game),
                                    isLandscape: size.width > size.height,
                                    canLaunch: store.systemFilesReady && runtimeState.canLaunch,
                                    liveStatus: liveStatusStore.status(for: game),
                                    isFavorite: isFavorite(game),
                                    launch: {
                                        markRecentlyPlayed(game)
                                        launchGame(game)
                                    },
                                    addCover: { addCover(game) },
                                    copyLaunchLink: { copyLaunchLink(game) },
                                    importConfig: { importConfig(game) },
                                    clearShaderCache: { clearShaderCache(game) },
                                    editGameData: { editGameData(game) },
                                    toggleFavorite: { toggleFavorite(game) },
                                    requestRemoveGame: { requestRemoveGame(game) }
                                )
                            }
                        }
                    } else {
                        let activeColumnCount = gameLibraryColumnCount(for: size)
                        LazyVGrid(columns: GameLibraryGridMetrics.columns(for: activeColumnCount),
                                  alignment: .center,
                                  spacing: GameLibraryGridMetrics.spacing(for: activeColumnCount) + 6) {
                            ForEach(displayedGames) { game in
                                GameCoverTile(
                                    game: game,
                                    canLaunch: store.systemFilesReady && runtimeState.canLaunch,
                                    liveStatus: liveStatusStore.status(for: game),
                                    isFavorite: isFavorite(game),
                                    launch: {
                                        markRecentlyPlayed(game)
                                        launchGame(game)
                                    },
                                    addCover: { addCover(game) },
                                    copyLaunchLink: { copyLaunchLink(game) },
                                    importConfig: { importConfig(game) },
                                    clearShaderCache: { clearShaderCache(game) },
                                    toggleFavorite: { toggleFavorite(game) },
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
        }
        .contextMenu {
            addGameContextMenuItem
        }
    }

    private var libraryBackgroundContextMenu: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .contentShape(Rectangle())
            .contextMenu {
                addGameContextMenuItem
            }
    }

    private var addGameContextMenuItem: some View {
        Button(action: importGames) {
            Label("Add Game", systemImage: "plus.circle")
        }
    }

    private var sortMode: GameLibrarySortMode {
        GameLibrarySortMode(rawValue: sortModeRawValue) ?? .title
    }

    private var sortModeBinding: Binding<GameLibrarySortMode> {
        Binding(
            get: { sortMode },
            set: { sortModeRawValue = $0.rawValue }
        )
    }

    private var sortedGames: [LibraryFile] {
        let games = store.games

        switch sortMode {
        case .favorites:
            return games
                .filter(isFavorite)
                .sorted(by: titleSort)
        case .title:
            return games.sorted(by: titleSort)
        case .live:
            return games.filter { game in
                liveStatusStore.status(for: game)?.isSupported == true
            }
            .sorted { lhs, rhs in
                let lhsScore = liveSortScore(for: lhs)
                let rhsScore = liveSortScore(for: rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return titleSort(lhs, rhs)
            }
        case .recent:
            return games.filter { game in
                recentlyPlayedTime(for: game) > 0
            }
            .sorted { lhs, rhs in
                let lhsTime = recentlyPlayedTime(for: lhs)
                let rhsTime = recentlyPlayedTime(for: rhs)
                if lhsTime != rhsTime {
                    return lhsTime > rhsTime
                }
                return titleSort(lhs, rhs)
            }
        }
    }

    private var emptyFilterTitle: String {
        switch sortMode {
        case .favorites:
            return "No Favorite Games"
        case .live:
            return "No Live Games"
        case .recent:
            return "No Recent Games"
        case .title:
            return "No Games"
        }
    }

    private var emptyFilterSystemImage: String {
        switch sortMode {
        case .favorites:
            return "star"
        case .live:
            return "antenna.radiowaves.left.and.right"
        case .recent:
            return "clock"
        case .title:
            return "opticaldisc"
        }
    }

    private func isFavorite(_ game: LibraryFile) -> Bool {
        favoriteGameKeys.contains(GameLibraryFavorites.key(for: game))
    }

    private func toggleFavorite(_ game: LibraryFile) {
        let key = GameLibraryFavorites.key(for: game)
        if favoriteGameKeys.contains(key) {
            favoriteGameKeys.remove(key)
        } else {
            favoriteGameKeys.insert(key)
        }
        GameLibraryFavorites.save(favoriteGameKeys)
    }

    private func markRecentlyPlayed(_ game: LibraryFile) {
        recentlyPlayedGameTimes[game.libraryIdentityKey] = Date().timeIntervalSince1970
        GameLibraryRecents.save(recentlyPlayedGameTimes)
    }

    private func titleSort(_ lhs: LibraryFile, _ rhs: LibraryFile) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private func liveSortScore(for game: LibraryFile) -> Int {
        guard let status = liveStatusStore.status(for: game), status.isSupported else {
            return 0
        }
        return status.hasPlayersOnline ? 2 : 1
    }

    private func recentlyPlayedTime(for game: LibraryFile) -> TimeInterval {
        recentlyPlayedGameTimes[game.libraryIdentityKey] ?? 0
    }

    private func gameLibraryColumnCount(for size: CGSize) -> Int {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return store.landscapeGameLibraryColumnCount.columnCount
        #else
        let isLandscape = size.width > size.height
        return isLandscape
            ? store.landscapeGameLibraryColumnCount.columnCount
            : store.portraitGameLibraryColumnCount.columnCount
        #endif
    }

    private var gameLibraryListViewEnabled: Bool {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return false
        #else
        return store.gameLibraryListViewEnabled
        #endif
    }
}

private struct GameLibraryFilterEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}
