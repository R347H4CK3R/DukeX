import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

private enum MainTab: Hashable, CaseIterable {
    case games
    case profile
    case settings

    var title: String {
        switch self {
        case .games:
            return "Games"
        case .profile:
            return "Profile"
        case .settings:
            return "Settings"
        }
    }
}

private struct FriendProfileImageSelectionTarget {
    let key: String
    let title: String
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: EmulatorFileStore
    @StateObject private var runtime = EmulatorCoreRuntime()
    @StateObject private var autoJIT = StikDebugAutoJITCoordinator()
    @StateObject private var profileStore = InsigniaProfileStore()
    @StateObject private var socialStore = XBLiveSocialStore()
    @StateObject private var activityFeedStore = XBLiveActivityFeedStore()
    @StateObject private var emulatorPresence = XBLiveEmulatorPresenceCoordinator()
    @StateObject private var liveStatusStore = InsigniaLiveStatusStore()
    @StateObject private var gameMetadataStore = GameMetadataStore()
    @AppStorage("DukeX.desktop.activityFeedWidth") private var activityFeedWidth = 340.0
    @AppStorage("DukeX.desktop.activityFeedExpanded") private var isActivityFeedExpanded = true
    @State private var importTarget: ImportTarget?
    @State private var autoLaunchAttempted = false
    @State private var coverSelectionTarget: LibraryFile?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isCoverPickerPresented = false
    @State private var selectedProfileImageItem: PhotosPickerItem?
    @State private var isProfileImagePickerPresented = false
    @State private var friendProfileImageTarget: FriendProfileImageSelectionTarget?
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
    @State private var lastObservedRuntimeState: EmulatorCoreRuntime.RunState?
    @State private var activityFriendTarget: ActivityFeedFriendTarget?

    private let tabRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let theme = DukeXTheme(mode: store.themeMode)
        let tabBarBackgroundVisibility: Visibility = theme.usesAnimatedBackground ? .hidden : .automatic
        let navigationBarBackgroundVisibility: Visibility = theme.usesAnimatedBackground ? .hidden : .automatic

        ZStack {
            if theme.usesAnimatedBackground {
                NostalgicDotBackgroundView()
            } else {
                theme.screenBackground
                    .ignoresSafeArea()
            }

            mainContent(
                tabBarBackgroundVisibility: tabBarBackgroundVisibility,
                navigationBarBackgroundVisibility: navigationBarBackgroundVisibility
            )
            .sheet(isPresented: $isProfileLoginPresented) {
                ProfileLoginView(profileStore: profileStore)
            }
            .sheet(item: $activityFriendTarget) { target in
                NavigationStack {
                    ActivityFeedFriendDetailView(
                        username: target.username,
                        profileStore: profileStore,
                        socialStore: socialStore,
                        installedGames: store.games,
                        inviteEligibleGames: gameInviteEligibleGames,
                        launchGameFromInvite: launchGame,
                        changeFriendProfileImage: beginFriendProfileImageSelection,
                        changeSocialFriendProfileImage: beginSocialFriendProfileImageSelection
                    )
                }
                .frame(minWidth: 520, idealWidth: 640, minHeight: 680, idealHeight: 760)
                .tint(theme.accentColor)
                .accentColor(theme.accentColor)
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
            .onChange(of: selectedCoverItem) { item in
                handleSelectedCover(item)
            }
            .photosPicker(
                isPresented: $isProfileImagePickerPresented,
                selection: $selectedProfileImageItem,
                matching: .images
            )
            .onChange(of: selectedProfileImageItem) { item in
                handleSelectedProfileImage(item)
            }
            .photosPicker(
                isPresented: $isFriendProfileImagePickerPresented,
                selection: $selectedFriendProfileImageItem,
                matching: .images
            )
            .onChange(of: selectedFriendProfileImageItem) { item in
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
                isPresented: removalConfirmationPresented,
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
                lastObservedRuntimeState = runtime.state
                if !environmentRequestsAutoLaunch {
                    resumePendingAutoJITLaunchIfNeeded()
                }
            }
            .task {
                profileStore.refresh()
                await refreshProfileSocialNowIfAuthenticated()
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
            .onChange(of: scenePhase) { newPhase in
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
            .onChange(of: selectedTab) { newTab in
                if newTab == .profile {
                    refreshProfileTab()
                } else {
                    refreshGamesAndProfile()
                }
                if newTab == .settings {
                    refreshLibraryForSettings()
                }
            }
            .onChange(of: runtime.state) { newState in
                let oldState = lastObservedRuntimeState ?? newState
                handleRuntimeStateChange(from: oldState, to: newState)
                lastObservedRuntimeState = newState
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
                handleIncomingURL(url)
            }
        }
        .environment(\.dukeXTheme, theme)
        .tint(theme.accentColor)
        .accentColor(theme.accentColor)
        #if targetEnvironment(macCatalyst)
        .desktopReadableInterfaceScale()
        #endif
        .onAppear {
            DukeXTheme.applyUIKitAppearance(themeMode: store.themeMode)
        }
        .onChange(of: store.themeMode) { themeMode in
            DukeXTheme.applyUIKitAppearance(themeMode: themeMode)
        }
    }

    private var gameInviteEligibleGames: [LibraryFile] {
        store.games
            .filter { game in
                GameLaunchLink.url(for: game) != nil &&
                    liveStatusStore.status(for: game)?.isSupported == true
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    @ViewBuilder
    private func mainContent(
        tabBarBackgroundVisibility: Visibility,
        navigationBarBackgroundVisibility: Visibility
    ) -> some View {
        #if targetEnvironment(macCatalyst)
        desktopMainContent
        #else
        mobileMainContent(
            tabBarBackgroundVisibility: tabBarBackgroundVisibility,
            navigationBarBackgroundVisibility: navigationBarBackgroundVisibility
        )
        #endif
    }

    private func mobileMainContent(
        tabBarBackgroundVisibility: Visibility,
        navigationBarBackgroundVisibility: Visibility
    ) -> some View {
        TabView(selection: $selectedTab) {
            mobileGamesNavigationStack
                .tabItem {
                    Label("Games", systemImage: "gamecontroller")
                }
                .tag(MainTab.games)

            mobileProfileNavigationStack
                .onAppear {
                    refreshProfileTab()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(MainTab.profile)

            mobileSettingsNavigationStack
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .background(Color.clear)
        .toolbarBackground(tabBarBackgroundVisibility, for: .tabBar)
        .toolbarBackground(navigationBarBackgroundVisibility, for: .navigationBar)
    }

    private var mobileGamesNavigationStack: some View {
        NavigationStack {
            gamesScreen
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    appToolbar
                }
        }
    }

    private var mobileProfileNavigationStack: some View {
        NavigationStack {
            profileScreen
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    appToolbar
                }
        }
    }

    private var mobileSettingsNavigationStack: some View {
        NavigationStack {
            settingsScreen
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    appToolbar
                }
        }
    }

    #if targetEnvironment(macCatalyst)
    private var desktopMainContent: some View {
        Group {
            if desktopAuxiliaryToolboxIsExpanded {
                HStack(spacing: 0) {
                    desktopExpandedAuxiliaryToolbox
                    desktopContentColumn
                }
            } else {
                ZStack(alignment: .topLeading) {
                    desktopContentColumn

                    DesktopCollapsedToolboxButton(
                        title: desktopAuxiliaryToolboxTitle,
                        action: expandDesktopAuxiliaryToolbox
                    )
                    .padding(.leading, 20)
                    .padding(.top, 38)
                    .zIndex(3)
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            CatalystWindowChromeConfigurator()
                .frame(width: 0, height: 0)
        }
    }

    private var desktopAuxiliaryToolboxIsExpanded: Bool {
        isActivityFeedExpanded
    }

    private var desktopAuxiliaryToolboxTitle: String {
        "Activity Feed"
    }

    private func expandDesktopAuxiliaryToolbox() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            isActivityFeedExpanded = true
        }
    }

    private var desktopContentColumn: some View {
        VStack(spacing: 0) {
            DesktopTopChrome(selectedTab: $selectedTab)
            desktopSelectedTabContent
                .desktopSectionTopFade()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var desktopExpandedAuxiliaryToolbox: some View {
        ActivityFeedView(
            feedStore: activityFeedStore,
            profileStore: profileStore,
            socialStore: socialStore,
            width: $activityFeedWidth,
            isExpanded: $isActivityFeedExpanded,
            openFriend: openActivityFeedFriend
        )
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    @ViewBuilder
    private var desktopSelectedTabContent: some View {
        switch selectedTab {
        case .games:
            NavigationStack {
                gamesScreen
            }
            .toolbar(.hidden, for: .navigationBar)
        case .profile:
            NavigationStack {
                profileScreen
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                refreshProfileTab()
            }
        case .settings:
            NavigationStack {
                settingsScreen
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    #endif

    private var gamesScreen: some View {
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
    }

    private var profileScreen: some View {
        ProfileView(
            profileStore: profileStore,
            socialStore: socialStore,
            signIn: { isProfileLoginPresented = true },
            signOut: {
                socialStore.clear()
                emulatorPresence.stop(reason: "sign out")
                profileStore.signOut()
            },
            changeProfileImage: beginProfileImageSelection,
            changeFriendProfileImage: beginFriendProfileImageSelection,
            changeSocialFriendProfileImage: beginSocialFriendProfileImageSelection,
            installedGames: store.games,
            inviteEligibleGames: gameInviteEligibleGames,
            launchGameFromInvite: launchGame
        )
    }

    private var settingsScreen: some View {
        SettingsView(
            store: store,
            profileStore: profileStore,
            runtimeState: runtime.state,
            importSystemFiles: { importTarget = .systemFiles }
        )
    }

    private var environmentRequestsAutoLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XEMU_IOS_AUTO_LAUNCH_GAME"] == "1" ||
            environment["XEMU_IOS_AUTO_LAUNCH_DASHBOARD"] == "1"
    }

    private var removalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { removalConfirmationTarget != nil },
            set: { isPresented in
                if !isPresented {
                    removalConfirmationTarget = nil
                }
            }
        )
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
                .frame(width: 142, height: 30)
                .accessibilityLabel("DukeX")
        }
    }

    private func refreshGamesAndProfile() {
        refreshGamesTab()
        profileStore.refresh()
        refreshProfileSocialIfAuthenticated()
    }

    private func refreshProfileTab() {
        profileStore.refresh()
        refreshProfileSocialIfAuthenticated()
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
        refreshProfileSocialIfAuthenticated()
    }

    private func openActivityFeedFriend(_ username: String) {
        activityFriendTarget = ActivityFeedFriendTarget(username: username)
    }

    private func refreshProfileSocialIfAuthenticated() {
        Task { @MainActor in
            await refreshProfileSocialNowIfAuthenticated()
        }
    }

    @MainActor
    private func refreshProfileSocialNowIfAuthenticated() async {
        guard profileStore.session?.isAuthenticated == true else {
            socialStore.clear()
            return
        }

        configureSocialNotifications()
        configureEmulatorPresenceNotifications()
        await socialStore.refreshAll()
    }

    @MainActor
    private func configureSocialNotifications() {
        socialStore.configureLocalNotifications(
            customAvatarImage: { username in
                let key = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let image = profileStore.friendProfileImages[key] {
                    return image
                }

                if let friend = socialStore.messageableFriends.first(where: {
                    $0.key == key || $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
                }) {
                    return profileStore.friendProfileImages[friend.key]
                }

                return nil
            },
            gameTitle: { titleID, embeddedTitle in
                if let normalizedTitleID = GameLaunchLink.normalizedTitleID(titleID),
                   let game = store.game(matchingTitleID: normalizedTitleID) {
                    return game.displayName
                }

                let title = embeddedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                return title?.isEmpty == false ? title! : "Title \(titleID)"
            },
            gameLocalCoverURL: { titleID in
                guard let normalizedTitleID = GameLaunchLink.normalizedTitleID(titleID) else {
                    return nil
                }

                return store.game(matchingTitleID: normalizedTitleID)?.coverURL
            }
        )
    }

    @MainActor
    private func configureEmulatorPresenceNotifications() {
        emulatorPresence.onAuthenticationFailure = { message in
            store.message = UserMessage(
                title: "XB.Live Presence Not Synced",
                detail: message
            )
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
            launchRuntime(plan, target: target)
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
            if activeRuntimeWasGame,
               case .failed = newState {
                emulatorPresence.stop(reason: "launch failed")
            }
            if !newState.isRunning {
                activeRuntimeWasGame = false
            }
            return
        }

        switch newState {
        case .exited:
            activeRuntimeWasGame = false
            emulatorPresence.stop(reason: "game exit")
            Task { @MainActor in
                await pushCloudSavesAutomaticallyIfNeeded(reason: "game exit")
            }
        case .failed:
            activeRuntimeWasGame = false
            emulatorPresence.stop(reason: "runtime failed")
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
        friendProfileImageTarget = FriendProfileImageSelectionTarget(key: friend.key, title: friend.gamertag)
        selectedFriendProfileImageItem = nil
        isFriendProfileImagePickerPresented = true
    }

    private func beginSocialFriendProfileImageSelection(for friend: XBLiveSocialFriend) {
        friendProfileImageTarget = FriendProfileImageSelectionTarget(key: friend.key, title: friend.title)
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

    private func handleIncomingURL(_ url: URL) {
        if let callbackScheme = GameLibraryExportLink.callbackScheme(from: url) {
            handleGameLibraryExportRequest(callbackScheme: callbackScheme)
            return
        }

        handleLaunchLink(url)
    }

    private func handleGameLibraryExportRequest(callbackScheme: String) {
        Task { @MainActor in
            await store.prepareAndRefresh()

            guard let response = GameLibraryExportLink.response(
                for: store.games,
                metadata: { gameMetadataStore.metadata(for: $0) },
                callbackScheme: callbackScheme
            ) else {
                store.message = UserMessage(
                    title: "Library Export Failed",
                    detail: "DukeX could not prepare a game library response for \(callbackScheme)."
                )
                return
            }

            UIApplication.shared.open(response.callbackURL) { success in
                if !success {
                    Task { @MainActor in
                        store.message = UserMessage(
                            title: "Library Export Failed",
                            detail: "DukeX prepared \(response.gameCount) game\(response.gameCount == 1 ? "" : "s"), but could not open \(callbackScheme)."
                        )
                    }
                }
            }
        }
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
        guard let item, let target = friendProfileImageTarget else {
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
                try profileStore.assignFriendProfileImage(data, key: target.key)
            } catch {
                store.message = UserMessage(title: "\(target.title) Picture Not Added", detail: error.localizedDescription)
            }
        }
    }

    private func launchWithoutAutoJIT(_ target: AutoJITLaunchTarget) {
        do {
            let plan = try makePlan(for: target)
            activeRuntimeWasGame = target == .game
            launchRuntime(plan, target: target)
        } catch {
            store.message = UserMessage(title: "Launch Blocked", detail: error.localizedDescription)
        }
    }

    private func launchRuntime(_ plan: XemuLaunchPlan, target: AutoJITLaunchTarget) {
        if target == .game {
            emulatorPresence.start(titleID: plan.titleID, gameName: plan.gameName)
        } else {
            emulatorPresence.stop(reason: "dashboard launch")
        }
        runtime.launch(plan: plan)
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

#if targetEnvironment(macCatalyst)
private struct DesktopSectionTopFadeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 22)

                    Rectangle()
                        .fill(.black)
                }
            }
    }
}

private extension View {
    func desktopSectionTopFade() -> some View {
        modifier(DesktopSectionTopFadeModifier())
    }

    func desktopReadableInterfaceScale() -> some View {
        dynamicTypeSize(.xxLarge)
            .controlSize(.large)
    }
}

private struct DesktopTopChrome: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        VStack(spacing: 14) {
            Picker("Section", selection: $selectedTab) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 293)
            .accessibilityLabel("Section")

            Image("DukeXLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 142, height: 30)
                .accessibilityLabel("DukeX")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }
}

private struct DesktopCollapsedToolboxButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(title)")
    }
}

private struct CatalystWindowChromeConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        CatalystWindowChromeView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? CatalystWindowChromeView)?.configureSoon()
    }
}

private final class CatalystWindowChromeView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureSoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureSoon()
    }

    fileprivate func configureSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.configure()
        }
    }

    private func configure() {
        window?.windowScene?.title = ""

        guard let titlebar = window?.windowScene?.titlebar else {
            return
        }

        titlebar.titleVisibility = .hidden
        titlebar.toolbar = nil
    }
}
#endif
