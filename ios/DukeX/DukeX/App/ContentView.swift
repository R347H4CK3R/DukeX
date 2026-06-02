import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

private enum MainTab: Hashable {
    case games
    case profile
    case settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: EmulatorFileStore
    @StateObject private var runtime = EmulatorCoreRuntime()
    @StateObject private var autoJIT = StikDebugAutoJITCoordinator()
    @StateObject private var profileStore = InsigniaProfileStore()
    @StateObject private var liveStatusStore = InsigniaLiveStatusStore()
    @StateObject private var gameMetadataStore = GameMetadataStore()
    @State private var importTarget: ImportTarget?
    @State private var autoLaunchAttempted = false
    @State private var coverSelectionTarget: LibraryFile?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isCoverPickerPresented = false
    @State private var selectedProfileImageItem: PhotosPickerItem?
    @State private var isProfileImagePickerPresented = false
    @State private var friendProfileImageTarget: InsigniaFriend?
    @State private var selectedFriendProfileImageItem: PhotosPickerItem?
    @State private var isFriendProfileImagePickerPresented = false
    @State private var configImportTarget: LibraryFile?
    @State private var gameMetadataTarget: LibraryFile?
    @State private var removalConfirmationTarget: LibraryFile?
    @State private var isProfileLoginPresented = false
    @State private var selectedTab: MainTab = .games
    @State private var isGamesAutoRefreshRunning = false
    @State private var isAutomaticCloudSaveSyncRunning = false
    @State private var activeRuntimeWasGame = false

    private let tabRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let theme = DukeXTheme(mode: store.themeMode)
        let tabBarBackgroundVisibility: Visibility = theme.usesAnimatedBackground ? .hidden : .automatic

        ZStack {
            if theme.usesAnimatedBackground {
                NostalgicDotBackgroundView()
            } else {
                theme.screenBackground
                    .ignoresSafeArea()
            }

            TabView(selection: $selectedTab) {
                NavigationStack {
                    GamesLibraryView(
                        runtimeState: runtime.state,
                        liveStatusStore: liveStatusStore,
                        metadataStore: gameMetadataStore,
                        launchDashboard: launchDashboard,
                        launchGame: launchGame,
                        importGames: { importTarget = .games },
                        addCover: beginCoverSelection,
                        copyLaunchLink: copyLaunchLink,
                        importConfig: beginConfigImport,
                        clearShaderCache: clearShaderCache,
                        editGameData: { gameMetadataTarget = $0 },
                        requestRemoveGame: { removalConfirmationTarget = $0 },
                        launchManicEmu: store.themeMode == .manicFeelings ? openManicEmu : nil,
                        openXBLive: store.themeMode == .livingOriginal ? openXBLive : nil
                    )
                    .navigationTitle("DukeX")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        appToolbar
                    }
                }
                .tabItem {
                    Label("Games", systemImage: "gamecontroller")
                }
                .tag(MainTab.games)

                NavigationStack {
                    ProfileView(
                        profileStore: profileStore,
                        signIn: { isProfileLoginPresented = true },
                        signOut: profileStore.signOut,
                        changeProfileImage: beginProfileImageSelection,
                        changeFriendProfileImage: beginFriendProfileImageSelection
                    )
                    .navigationTitle("DukeX")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        appToolbar
                    }
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(MainTab.profile)

                NavigationStack {
                    SettingsView(
                        store: store,
                        profileStore: profileStore,
                        runtimeState: runtime.state,
                        autoJITStatus: autoJIT.status,
                        importSystemFiles: { importTarget = .systemFiles },
                        importSkins: { importTarget = .skins }
                    )
                        .navigationTitle("DukeX")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            appToolbar
                        }
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
            }
            .background(Color.clear)
            .toolbarBackground(tabBarBackgroundVisibility, for: .tabBar)
            .sheet(isPresented: $isProfileLoginPresented) {
                ProfileLoginView(profileStore: profileStore)
            }
            .sheet(item: $gameMetadataTarget) { game in
                GameMetadataEditorView(
                    game: game,
                    metadata: gameMetadataStore.metadata(for: game),
                    save: { metadata in
                        gameMetadataStore.setMetadata(metadata, for: game)
                    }
                )
            }
            .sheet(item: $importTarget) { target in
                DocumentImportPicker(
                    target: target,
                    onPick: { urls in
                        importTarget = nil
                        store.importFiles(urls, to: target)
                    },
                    onCancel: {
                        importTarget = nil
                    }
                )
            }
            .fileImporter(
                isPresented: Binding(
                    get: { configImportTarget != nil },
                    set: { if !$0 { configImportTarget = nil } }
                ),
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                let target = configImportTarget
                configImportTarget = nil

                guard let target else {
                    return
                }

                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        return
                    }
                    do {
                        try store.importCustomConfig(url, for: target)
                    } catch {
                        store.message = UserMessage(title: "Config Not Imported", detail: error.localizedDescription)
                    }
                case .failure(let error):
                    store.message = UserMessage(title: "Config Not Imported", detail: error.localizedDescription)
                }
            }
            .photosPicker(
                isPresented: $isCoverPickerPresented,
                selection: $selectedCoverItem,
                matching: .images
            )
            .onChange(of: selectedCoverItem) { _, item in
                handleSelectedCover(item)
            }
            .photosPicker(
                isPresented: $isProfileImagePickerPresented,
                selection: $selectedProfileImageItem,
                matching: .images
            )
            .onChange(of: selectedProfileImageItem) { _, item in
                handleSelectedProfileImage(item)
            }
            .photosPicker(
                isPresented: $isFriendProfileImagePickerPresented,
                selection: $selectedFriendProfileImageItem,
                matching: .images
            )
            .onChange(of: selectedFriendProfileImageItem) { _, item in
                handleSelectedFriendProfileImage(item)
            }
            .alert(item: $store.message) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.detail),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Remove Game",
                isPresented: Binding(
                    get: { removalConfirmationTarget != nil },
                    set: { if !$0 { removalConfirmationTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let game = removalConfirmationTarget {
                    Button("Remove \(game.displayName)", role: .destructive) {
                        removeGame(game)
                    }
                }
                Button("Cancel", role: .cancel) {
                    removalConfirmationTarget = nil
                }
            } message: {
                if let game = removalConfirmationTarget {
                    Text("Are you sure you would like to remove \(game.displayName) and all of its data?")
                }
            }
            .sheet(item: $store.launchPlan) { plan in
                LaunchPlanView(plan: plan)
            }
            .onAppear {
                if !environmentRequestsAutoLaunch {
                    resumePendingAutoJITLaunchIfNeeded()
                }
            }
            .task {
                profileStore.refresh()
                await refreshGamesNow()
                await pullCloudSavesAutomaticallyIfNeeded(reason: "launch")
                if environmentRequestsAutoLaunch && !autoLaunchAttempted {
                    autoJIT.clearPendingForFreshAutomaticLaunch()
                }
                if resumePendingAutoJITLaunchIfNeeded() {
                    return
                }
                autoLaunchIfRequested()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    autoJIT.markAppReturnedFromStikDebugIfPending()
                    resumePendingAutoJITLaunchIfNeeded()
                case .inactive, .background:
                    autoJIT.markAppLeftForStikDebugIfPending()
                @unknown default:
                    break
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                refreshGamesAndProfile()
                if newTab == .settings {
                    refreshLibraryForSettings()
                }
            }
            .onChange(of: runtime.state) { oldState, newState in
                handleRuntimeStateChange(from: oldState, to: newState)
            }
            .onReceive(tabRefreshTimer) { _ in
                guard scenePhase == .active else {
                    return
                }
                refreshOpenTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dukeXReturnToGamesRequested)) { _ in
                selectedTab = .games
            }
            .onOpenURL { url in
                handleLaunchLink(url)
            }
        }
        .environment(\.dukeXTheme, theme)
        .tint(theme.accentColor)
        .accentColor(theme.accentColor)
        .onAppear {
            DukeXTheme.applyUIKitAppearance(themeMode: store.themeMode)
        }
        .onChange(of: store.themeMode) { _, themeMode in
            DukeXTheme.applyUIKitAppearance(themeMode: themeMode)
        }
    }

    private var environmentRequestsAutoLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XEMU_IOS_AUTO_LAUNCH_GAME"] == "1" ||
            environment["XEMU_IOS_AUTO_LAUNCH_DASHBOARD"] == "1"
    }

    private func refreshLibraryForSettings() {
        do {
            try store.refresh()
        } catch {
            store.message = UserMessage(title: "Library Not Refreshed", detail: error.localizedDescription)
        }
    }

    @ToolbarContentBuilder
    private var appToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Image("DukeXLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 25)
                .accessibilityLabel("DukeX")
        }
    }

    private func refreshGamesAndProfile() {
        refreshGamesTab()
        profileStore.refresh()
    }

    private func refreshOpenTab() {
        switch selectedTab {
        case .games:
            refreshGamesTab()
        case .profile:
            profileStore.refresh()
        case .settings:
            break
        }
    }

    private func refreshGamesTab() {
        Task { @MainActor in
            await refreshGamesNow()
        }
    }

    @MainActor
    private func refreshGamesNow() async {
        guard !isGamesAutoRefreshRunning else {
            return
        }

        isGamesAutoRefreshRunning = true
        defer { isGamesAutoRefreshRunning = false }

        await store.prepareAndRefresh()
        runtime.refresh()
        liveStatusStore.refresh()
    }

    @MainActor
    private func pullCloudSavesAutomaticallyIfNeeded(reason: String) async {
        await runAutomaticCloudSaveSync(reason: reason) { sessionKey, hdd, eeprom, directoryURL in
            let result = try await XBLCloudSaveService().pullRemoteSaves(
                sessionKey: sessionKey,
                hdd: hdd,
                eeprom: eeprom,
                cloudSavesDirectoryURL: directoryURL
            )
            NSLog("DukeX automatic cloud save pull completed: %@", result.pullDetail)
        }
    }

    @MainActor
    private func pushCloudSavesAutomaticallyIfNeeded(reason: String) async {
        await runAutomaticCloudSaveSync(reason: reason) { sessionKey, hdd, eeprom, directoryURL in
            let result = try await XBLCloudSaveService().pushLocalSaves(
                sessionKey: sessionKey,
                hdd: hdd,
                eeprom: eeprom,
                cloudSavesDirectoryURL: directoryURL,
                games: store.games
            )
            NSLog("DukeX automatic cloud save push completed: %@", result.pushDetail)
        }
    }

    @MainActor
    private func runAutomaticCloudSaveSync(
        reason: String,
        operation: @escaping (
            _ sessionKey: String,
            _ hdd: LibraryFile,
            _ eeprom: LibraryFile,
            _ cloudSavesDirectoryURL: URL
        ) async throws -> Void
    ) async {
        guard store.cloudSaveSyncEnabled else {
            return
        }
        guard !runtime.state.isRunning,
              !isAutomaticCloudSaveSyncRunning else {
            return
        }
        guard let sessionKey = try? InsigniaProfileStore.storedSessionKey(),
              !sessionKey.isEmpty else {
            NSLog("DukeX automatic cloud save sync skipped (%@): missing xb.live session", reason)
            return
        }
        guard let hdd = store.hdd else {
            NSLog("DukeX automatic cloud save sync skipped (%@): missing HDD", reason)
            return
        }
        guard let eeprom = store.eeprom else {
            NSLog("DukeX automatic cloud save sync skipped (%@): missing EEPROM", reason)
            return
        }

        isAutomaticCloudSaveSyncRunning = true
        defer {
            isAutomaticCloudSaveSyncRunning = false
        }

        do {
            try store.prepareCloudSaveDirectory()
            try await operation(sessionKey, hdd, eeprom, store.cloudSavesDirectoryURL)
        } catch {
            NSLog(
                "DukeX automatic cloud save sync failed (%@): %@",
                reason,
                error.localizedDescription
            )
        }
    }

    private func launchGame() {
        do {
            try launch(.game)
        } catch {
            store.message = UserMessage(title: "Launch Blocked", detail: error.localizedDescription)
        }
    }

    private func launchGame(_ game: LibraryFile) {
        store.selectedGameID = game.id
        launchGame()
    }

    private func launchDashboard() {
        do {
            try launch(.dashboard)
        } catch {
            store.message = UserMessage(title: "Launch Blocked", detail: error.localizedDescription)
        }
    }

    private func launch(_ target: AutoJITLaunchTarget) throws {
        let plan = try makePlan(for: target)
        activeRuntimeWasGame = target == .game
        guard plan.requiresJITHandoff && store.autoJITBeforeLaunchEnabled else {
            runtime.launch(plan: plan)
            return
        }

        try runtime.prepareBeforeAutoJIT()
        autoJIT.requestJIT(for: target, scriptName: plan.jitMode.stikDebugScriptName) { message in
            store.message = message
        }
        scheduleAutoJITFallbackIfNeeded()
    }

    private func handleRuntimeStateChange(
        from oldState: EmulatorCoreRuntime.RunState,
        to newState: EmulatorCoreRuntime.RunState
    ) {
        guard activeRuntimeWasGame,
              oldState.isRunning else {
            if !newState.isRunning {
                activeRuntimeWasGame = false
            }
            return
        }

        switch newState {
        case .exited:
            activeRuntimeWasGame = false
            Task { @MainActor in
                await pushCloudSavesAutomaticallyIfNeeded(reason: "game exit")
            }
        case .failed:
            activeRuntimeWasGame = false
        default:
            break
        }
    }

    private func beginCoverSelection(for game: LibraryFile) {
        coverSelectionTarget = game
        selectedCoverItem = nil
        isCoverPickerPresented = true
    }

    private func beginProfileImageSelection() {
        selectedProfileImageItem = nil
        isProfileImagePickerPresented = true
    }

    private func beginFriendProfileImageSelection(for friend: InsigniaFriend) {
        friendProfileImageTarget = friend
        selectedFriendProfileImageItem = nil
        isFriendProfileImagePickerPresented = true
    }

    private func beginConfigImport(for game: LibraryFile) {
        configImportTarget = game
    }

    private func copyLaunchLink(for game: LibraryFile) {
        guard let url = GameLaunchLink.url(for: game) else {
            store.message = UserMessage(
                title: "Launch Link Unavailable",
                detail: "\(game.displayName) does not have a readable TitleID."
            )
            return
        }

        UIPasteboard.general.string = url.absoluteString
        store.message = UserMessage(
            title: "Launch Link Copied",
            detail: url.absoluteString
        )
    }

    private func openManicEmu() {
        guard let launchURL = URL(string: "manicemu://launch"),
              let fallbackURL = URL(string: "https://github.com/Manic-EMU/ManicEMU/releases") else {
            return
        }

        let application = UIApplication.shared
        if application.canOpenURL(launchURL) {
            application.open(launchURL)
        } else {
            application.open(fallbackURL)
        }
    }

    private func openXBLive() {
        guard let url = URL(string: "https://xb.live/") else {
            return
        }

        UIApplication.shared.open(url)
    }

    private func handleLaunchLink(_ url: URL) {
        guard let titleID = GameLaunchLink.titleID(from: url) else {
            return
        }

        selectedTab = .games
        Task { @MainActor in
            await store.prepareAndRefresh()
            guard let game = store.game(matchingTitleID: titleID) else {
                store.message = UserMessage(
                    title: "Game Not Found",
                    detail: "No installed game matched TitleID \(titleID)."
                )
                return
            }

            launchGame(game)
        }
    }

    private func clearShaderCache(for game: LibraryFile) {
        do {
            try store.clearShaderCache(for: game)
        } catch {
            store.message = UserMessage(title: "Shader Cache Not Cleared", detail: error.localizedDescription)
        }
    }

    private func removeGame(_ game: LibraryFile) {
        defer {
            removalConfirmationTarget = nil
        }

        do {
            try store.removeGame(game)
        } catch {
            store.message = UserMessage(title: "Game Not Removed", detail: error.localizedDescription)
        }
    }

    private func handleSelectedCover(_ item: PhotosPickerItem?) {
        guard let item, let game = coverSelectionTarget else {
            return
        }

        Task { @MainActor in
            defer {
                selectedCoverItem = nil
                coverSelectionTarget = nil
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CoverSelectionError.emptySelection
                }
                try store.assignCover(data, to: game)
            } catch {
                store.message = UserMessage(title: "Cover Not Added", detail: error.localizedDescription)
            }
        }
    }

    private func handleSelectedProfileImage(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task { @MainActor in
            defer {
                selectedProfileImageItem = nil
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CoverSelectionError.emptySelection
                }
                try profileStore.assignProfileImage(data)
            } catch {
                store.message = UserMessage(title: "Profile Picture Not Added", detail: error.localizedDescription)
            }
        }
    }

    private func handleSelectedFriendProfileImage(_ item: PhotosPickerItem?) {
        guard let item, let friend = friendProfileImageTarget else {
            return
        }

        Task { @MainActor in
            defer {
                selectedFriendProfileImageItem = nil
                friendProfileImageTarget = nil
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CoverSelectionError.emptySelection
                }
                try profileStore.assignFriendProfileImage(data, to: friend)
            } catch {
                store.message = UserMessage(title: "Friend Picture Not Added", detail: error.localizedDescription)
            }
        }
    }

    private func launchWithoutAutoJIT(_ target: AutoJITLaunchTarget) {
        do {
            runtime.launch(plan: try makePlan(for: target))
        } catch {
            store.message = UserMessage(title: "Launch Blocked", detail: error.localizedDescription)
        }
    }

    private func makePlan(for target: AutoJITLaunchTarget) throws -> XemuLaunchPlan {
        switch target {
        case .dashboard:
            return try store.makeDashboardLaunchPlan()
        case .game:
            return try store.makeLaunchPlan()
        }
    }

    @discardableResult
    private func resumePendingAutoJITLaunchIfNeeded() -> Bool {
        guard autoJIT.hasPendingLaunch else {
            return false
        }
        guard let target = autoJIT.consumePendingLaunchIfReady() else {
            if autoJIT.hasObservedStikDebugTrip {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if UIApplication.shared.applicationState == .active {
                        resumePendingAutoJITLaunchIfNeeded()
                    }
                }
            }
            scheduleAutoJITFallbackIfNeeded()
            return true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            launchWithoutAutoJIT(target)
        }
        return true
    }

    private func autoLaunchIfRequested() {
        guard !autoLaunchAttempted else {
            return
        }
        guard !autoJIT.hasPendingLaunch else {
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let shouldAutoLaunchGame = environment["XEMU_IOS_AUTO_LAUNCH_GAME"] == "1"
        let shouldAutoLaunchDashboard =
            store.autoLaunchDashboardOnOpenEnabled ||
            environment["XEMU_IOS_AUTO_LAUNCH_DASHBOARD"] == "1"
        guard shouldAutoLaunchGame || shouldAutoLaunchDashboard else {
            return
        }
        guard shouldAutoLaunchGame || !autoJIT.shouldSuppressAutomaticDashboardLaunch else {
            return
        }

        autoLaunchAttempted = true
        if shouldAutoLaunchGame {
            launchGame()
        } else if shouldAutoLaunchDashboard {
            autoJIT.noteAutomaticDashboardLaunchAttempt()
            launchDashboard()
        }
    }

    private func scheduleAutoJITFallbackIfNeeded() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            guard autoJIT.hasPendingLaunch,
                  UIApplication.shared.applicationState == .active,
                  runtime.state.canLaunch else {
                return
            }
            autoJIT.forcePendingLaunchReady()
            resumePendingAutoJITLaunchIfNeeded()
        }
    }
}
