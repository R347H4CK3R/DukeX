import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI
import SafariServices

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
    @State private var importTarget: ImportTarget?
    @State private var autoLaunchAttempted = false
    @State private var coverSelectionTarget: LibraryFile?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isCoverPickerPresented = false
    @State private var selectedProfileImageItem: PhotosPickerItem?
    @State private var isProfileImagePickerPresented = false
    @State private var configImportTarget: LibraryFile?
    @State private var removalConfirmationTarget: LibraryFile?
    @State private var isProfileLoginPresented = false
    @State private var isInsigniaDashboardPresented = false
    @State private var selectedTab: MainTab = .games

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GamesLibraryView(
                    runtimeState: runtime.state,
                    launchDashboard: launchDashboard,
                    launchGame: launchGame,
                    importGames: { importTarget = .games },
                    addCover: beginCoverSelection,
                    importConfig: beginConfigImport,
                    clearShaderCache: clearShaderCache,
                    requestRemoveGame: { removalConfirmationTarget = $0 }
                )
                .navigationTitle("DukeX")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    appToolbar(showsRefreshButton: true)
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
                    openDashboard: { isInsigniaDashboardPresented = true },
                    changeProfileImage: beginProfileImageSelection
                )
                .navigationTitle("DukeX")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    profileToolbar
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(MainTab.profile)

            NavigationStack {
                settingsList
                    .navigationTitle("DukeX")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        appToolbar(showsRefreshButton: false)
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .sheet(isPresented: $isProfileLoginPresented) {
            ProfileLoginView(
                profileStore: profileStore,
                openDashboard: { isInsigniaDashboardPresented = true }
            )
        }
        .sheet(isPresented: $isInsigniaDashboardPresented) {
            InsigniaDashboardView(url: InsigniaPublicService.dashboardURL)
                .ignoresSafeArea()
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
            runtime.refresh()
            if !environmentRequestsAutoLaunch {
                resumePendingAutoJITLaunchIfNeeded()
            }
        }
        .task {
            await store.prepareAndRefresh()
            runtime.refresh()
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
            if newTab == .profile {
                profileStore.refresh()
            }
        }
    }

    private var environmentRequestsAutoLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XEMU_IOS_AUTO_LAUNCH_GAME"] == "1" ||
            environment["XEMU_IOS_AUTO_LAUNCH_DASHBOARD"] == "1"
    }

    private var settingsList: some View {
        List {
            Section("Runtime") {
                Toggle(isOn: $store.universalJITEnabled) {
                    Label("Universal.js JIT", systemImage: "bolt.horizontal.circle")
                }

                Text("Required for devices running iOS 26 or later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.autoJITBeforeLaunchEnabled) {
                    Label("Auto-enable via StikDebug", systemImage: "arrow.triangle.2.circlepath")
                }

                Text("Automatically enables JIT before launching a game.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.autoLaunchDashboardOnOpenEnabled) {
                    Label("Auto Launch Dashboard", systemImage: "rectangle.grid.1x2.fill")
                }

                Text("Recommended only if you use XBMC or another replacement dashboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                CoreStatusRow(state: runtime.state)
                AutoJITStatusRow(status: autoJIT.status)
            }

            Section("Display") {
                Toggle(isOn: $store.metalHUDEnabled) {
                    Label("Metal HUD", systemImage: "gauge.with.dots.needle.67percent")
                }

                Text("Off by default. Changes apply the next time the emulator view starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker(selection: $store.presentPacingMode) {
                    ForEach(PresentPacingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("Present Pacing", systemImage: "speedometer")
                }
                .pickerStyle(.segmented)

                Text(store.presentPacingMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Network") {
                Toggle(isOn: $store.forceInsigniaNATEnabled) {
                    Label("Force NAT to Insignia", systemImage: "network")
                }

                Text("On by default. Uses Insignia DNS routing for Xbox Live services.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Group {
                    LabeledContent("DNS Server") {
                        TextField(NetworkSettings.insigniaDNSServer, text: $store.natDNSServer)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }

                    Picker(selection: $store.natPortProtocol) {
                        Text("UDP").tag("udp")
                        Text("TCP").tag("tcp")
                    } label: {
                        Label("Forward Protocol", systemImage: "arrow.left.arrow.right")
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Host Port") {
                        TextField(NetworkSettings.defaultHostPort, text: $store.natHostPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96)
                    }

                    LabeledContent("Guest Port") {
                        TextField(NetworkSettings.defaultGuestPort, text: $store.natGuestPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96)
                    }
                }
                .disabled(store.forceInsigniaNATEnabled)
                .opacity(store.forceInsigniaNATEnabled ? 0.45 : 1)
            }

            Section("System Files") {
                AssetRow(title: "Flash BIOS", file: store.bios, missingSystemImage: "memorychip")
                AssetRow(title: "MCPX", file: store.mcpx, missingSystemImage: "lock.rectangle")
                AssetRow(title: "EEPROM", file: store.eeprom, missingSystemImage: "key", missingText: "Generated automatically")
                AssetRow(title: "HDD", file: store.hdd, missingSystemImage: "internaldrive")

                Button {
                    importTarget = .systemFiles
                } label: {
                    Label("Import System Files", systemImage: "tray.and.arrow.down")
                }
            }

            Section("Folders") {
                FolderRow(title: "BIOS",
                          url: store.biosDirectoryURL,
                          storageUsed: store.folderStorageUsage.bios.displayText)
                FolderRow(title: "ROMs",
                          url: store.romsDirectoryURL,
                          storageUsed: store.folderStorageUsage.roms.displayText)
                FolderRow(title: "Covers",
                          url: store.coversDirectoryURL,
                          storageUsed: store.folderStorageUsage.covers.displayText)
            }

            Section {
                VStack(spacing: 4) {
                    Text("DukeX is dedicated to Lily")
                        .font(.footnote.weight(.semibold))
                    Text("Lily, you are loved and remembered")
                        .font(.footnote)
                    Text("11/03/2023")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        appToolbar(showsRefreshButton: false)

        ToolbarItem(placement: .topBarLeading) {
            Button {
                if profileStore.isSignedIn {
                    profileStore.signOut()
                } else {
                    isProfileLoginPresented = true
                }
            } label: {
                Image(systemName: profileStore.isSignedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.plus")
            }
            .accessibilityLabel(profileStore.isSignedIn ? "Sign Out" : "Sign In")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                profileStore.refresh()
            } label: {
                if profileStore.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(!profileStore.isSignedIn || profileStore.isRefreshing)
            .accessibilityLabel("Refresh Profile")
        }
    }

    @ToolbarContentBuilder
    private func appToolbar(showsRefreshButton: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Image("DukeXLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 25)
                .accessibilityLabel("DukeX")
        }

        if showsRefreshButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.prepareAndRefresh()
                        runtime.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
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
        guard plan.universalJITEnabled && store.autoJITBeforeLaunchEnabled else {
            runtime.launch(plan: plan)
            return
        }

        try runtime.prepareBeforeAutoJIT()
        autoJIT.requestJIT(for: target) { message in
            store.message = message
        }
        scheduleAutoJITFallbackIfNeeded()
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

    private func beginConfigImport(for game: LibraryFile) {
        configImportTarget = game
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

private struct GamesLibraryView: View {
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

private struct ProfileView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    let signIn: () -> Void
    let openDashboard: () -> Void
    let changeProfileImage: () -> Void

    var body: some View {
        List {
            if let session = profileStore.session {
                signedInContent(session)
            } else {
                signedOutContent
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func signedInContent(_ session: InsigniaProfileSession) -> some View {
        Section {
            ProfileHeaderRow(
                gamertag: session.gamertag,
                lastRefreshed: profileStore.lastRefreshedText,
                profileImage: profileStore.profileImage,
                changeProfileImage: changeProfileImage,
                clearProfileImage: profileStore.clearProfileImage
            )
        }

        Section("Account") {
            Button(action: openDashboard) {
                Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
            }

            Text("DukeX only stores your gamertag locally. Sign in through Insignia's web dashboard to manage the real account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Insignia Status") {
            ProfileInfoRow(title: "Users Online",
                           value: profileStore.usersOnlineText,
                           systemImage: "person.2.wave.2")
            ProfileInfoRow(title: "Registered Users",
                           value: profileStore.registeredUsersText,
                           systemImage: "person.3")
            ProfileInfoRow(title: "Games Supported",
                           value: profileStore.gamesSupportedText,
                           systemImage: "gamecontroller")
        }

        Section("Active Games") {
            if profileStore.activeGames.isEmpty {
                ProfileEmptyRow(title: "No public activity synced",
                                systemImage: "antenna.radiowaves.left.and.right")
            } else {
                ForEach(profileStore.activeGames) { game in
                    ProfileInfoRow(title: game.title,
                                   value: game.onlineUsers,
                                   detail: game.detail,
                                   systemImage: "play.circle")
                }
            }
        }
    }

    private var signedOutContent: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("Insignia Profile")
                        .font(.headline)
                    Text("Not signed in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: signIn) {
                    Label("Set Gamertag", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: openDashboard) {
                    Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }
}

private struct ProfileLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileStore: InsigniaProfileStore
    let openDashboard: () -> Void
    @State private var gamertag: String
    @State private var errorText: String?

    init(profileStore: InsigniaProfileStore, openDashboard: @escaping () -> Void) {
        self.profileStore = profileStore
        self.openDashboard = openDashboard
        _gamertag = State(initialValue: profileStore.session?.gamertag ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Insignia") {
                    TextField("Gamertag", text: $gamertag)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        dismiss()
                        openDashboard()
                    } label: {
                        Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
                    }
                }

                Section {
                    Label {
                        Text("Signing in here only powers the DukeX profile tab. It does not change the account tied to your Xbox dashboard. To play online through Insignia, keep Force NAT to Insignia enabled in Settings and make sure your dashboard is registered with Insignia's Xbox Live services.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        signIn()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func signIn() {
        do {
            try profileStore.signIn(gamertag: gamertag)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ProfileHeaderRow: View {
    let gamertag: String
    let lastRefreshed: String
    let profileImage: UIImage?
    let changeProfileImage: () -> Void
    let clearProfileImage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            avatar
                .contextMenu {
                    Button(action: changeProfileImage) {
                        Label("Change Profile Picture", systemImage: "photo")
                    }

                    if profileImage != nil {
                        Button(role: .destructive, action: clearProfileImage) {
                            Label("Remove Profile Picture", systemImage: "trash")
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(gamertag)
                    .font(.headline)
                Text("Last refresh: \(lastRefreshed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 72)
    }

    @ViewBuilder
    private var avatar: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Text(initial)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)
        }
    }

    private var initial: String {
        String(gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct ProfileInfoRow: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String

    init(title: String, value: String, detail: String? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 44)
    }
}

private struct ProfileEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}

private struct InsigniaProfileSession: Equatable {
    let gamertag: String
    let signedInAt: Date
}

private struct InsigniaPublicSnapshot: Codable, Equatable {
    let registeredUsers: String
    let gamesSupported: String
    let usersOnline: String
    let activeGames: [InsigniaActiveGame]
}

private struct InsigniaActiveGame: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let serial: String
    let onlineUsers: String
    let detail: String
}

private struct InsigniaDashboardView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}

private enum InsigniaPublicService {
    static let dashboardURL = URL(string: "https://insignia.live/dashboard/")!

    static func fetchPublicSnapshot() async throws -> InsigniaPublicSnapshot {
        let url = URL(string: "https://insignia.live/")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw ServiceError.unavailable
        }

        return InsigniaPublicSnapshot(
            registeredUsers: firstStatistic(named: "Registered Users", in: html) ?? "Unknown",
            gamesSupported: firstStatistic(named: "Games Supported", in: html) ?? "Unknown",
            usersOnline: firstStatistic(named: "Users Online Now", in: html) ?? "Unknown",
            activeGames: activeGames(from: html)
        )
    }

    private static func firstStatistic(named label: String, in html: String) -> String? {
        let pattern = "<h3>\\s*([0-9,]+)\\s*</h3>\\s*<p>\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*</p>"
        return firstMatch(pattern: pattern, in: html).first
    }

    private static func activeGames(from html: String) -> [InsigniaActiveGame] {
        let pattern = #"<tr>\s*<td>\s*<a href="[^"]+">\s*<img[\s\S]*?</a>\s*<a href="[^"]+">([\s\S]*?)</a>\s*<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td>\s*([\s\S]*?)<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td[^>]*>\s*([0-9]+)\s*</td>\s*<td[^>]*>\s*([\s\S]*?)\s*</td>"#

        return matches(pattern: pattern, in: html)
            .prefix(8)
            .compactMap { captures -> InsigniaActiveGame? in
                guard captures.count == 6 else {
                    return nil
                }

                let title = cleanedHTML(captures[0])
                let subtitle = cleanedHTML(captures[1])
                let publisherCode = cleanedHTML(captures[2])
                let titleID = cleanedHTML(captures[3])
                let onlineUsers = cleanedHTML(captures[4])
                let activePlayers = cleanedHTML(captures[5])
                let serial = [publisherCode, titleID]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                let detailParts = [serial, activePlayers]
                    .filter { !$0.isEmpty && $0 != "-" }
                let detail = detailParts.isEmpty ? "Public activity" : detailParts.joined(separator: " - ")

                return InsigniaActiveGame(
                    id: titleID.isEmpty ? title : titleID,
                    title: title.isEmpty ? subtitle : title,
                    serial: serial,
                    onlineUsers: onlineUsers,
                    detail: detail
                )
            }
    }

    private static func firstMatch(pattern: String, in text: String) -> [String] {
        matches(pattern: pattern, in: text).first ?? []
    }

    private static func matches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private static func cleanedHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = withoutTags
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = collapsed.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return collapsed
        }

        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Insignia service metadata is unavailable."
        }
    }
}

@MainActor
private final class InsigniaProfileStore: ObservableObject {
    @Published private(set) var session: InsigniaProfileSession?
    @Published private(set) var publicSnapshot: InsigniaPublicSnapshot?
    @Published private(set) var profileImage: UIImage?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isRefreshing = false

    private static let gamertagKey = "InsigniaProfileGamertag"
    private static let signedInAtKey = "InsigniaProfileSignedInAt"
    private static let lastRefreshedKey = "InsigniaProfileLastRefreshedAt"
    private static let publicSnapshotKey = "InsigniaPublicSnapshot"
    private static let profileImageFileName = "profile-picture.jpg"

    var isSignedIn: Bool {
        session != nil
    }

    var registeredUsersText: String {
        publicSnapshot?.registeredUsers ?? "Not Synced"
    }

    var gamesSupportedText: String {
        publicSnapshot?.gamesSupported ?? "Not Synced"
    }

    var usersOnlineText: String {
        publicSnapshot?.usersOnline ?? "Not Synced"
    }

    var activeGames: [InsigniaActiveGame] {
        publicSnapshot?.activeGames ?? []
    }

    var lastRefreshedText: String {
        guard let lastRefreshed else {
            return "Never"
        }

        return lastRefreshed.formatted(date: .omitted, time: .shortened)
    }

    init() {
        let defaults = UserDefaults.standard
        if let gamertag = defaults.string(forKey: Self.gamertagKey), !gamertag.isEmpty {
            let signedInAt = defaults.object(forKey: Self.signedInAtKey) as? Date ?? Date()
            session = InsigniaProfileSession(gamertag: gamertag, signedInAt: signedInAt)
        }
        lastRefreshed = defaults.object(forKey: Self.lastRefreshedKey) as? Date
        publicSnapshot = Self.loadPublicSnapshot()
        loadProfileImage()
    }

    func signIn(gamertag: String) throws {
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileSignInError.missingGamertag
        }

        let signedInAt = Date()
        session = InsigniaProfileSession(gamertag: trimmed, signedInAt: signedInAt)
        lastRefreshed = nil

        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: Self.gamertagKey)
        defaults.set(signedInAt, forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
    }

    func signOut() {
        session = nil
        lastRefreshed = nil
        isRefreshing = false

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.gamertagKey)
        defaults.removeObject(forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
    }

    func assignProfileImage(_ data: Data) throws {
        let image = UIImage(data: data)
        let imageData = image?.jpegData(compressionQuality: 0.9) ?? data
        try FileManager.default.createDirectory(at: profileDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try imageData.write(to: profileImageURL, options: .atomic)
        profileImage = UIImage(data: imageData)
    }

    func clearProfileImage() {
        try? FileManager.default.removeItem(at: profileImageURL)
        profileImage = nil
    }

    func refresh() {
        guard isSignedIn, !isRefreshing else {
            return
        }

        isRefreshing = true
        Task { @MainActor in
            do {
                let snapshot = try await InsigniaPublicService.fetchPublicSnapshot()
                publicSnapshot = snapshot
                Self.savePublicSnapshot(snapshot)

                let refreshedAt = Date()
                lastRefreshed = refreshedAt
                UserDefaults.standard.set(refreshedAt, forKey: Self.lastRefreshedKey)
            } catch {
            }

            isRefreshing = false
        }
    }

    private static func loadPublicSnapshot() -> InsigniaPublicSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: publicSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(InsigniaPublicSnapshot.self, from: data)
    }

    private static func savePublicSnapshot(_ snapshot: InsigniaPublicSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: publicSnapshotKey)
    }

    private var profileDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profile", isDirectory: true)
    }

    private var profileImageURL: URL {
        profileDirectoryURL.appendingPathComponent(Self.profileImageFileName)
    }

    private func loadProfileImage() {
        guard let data = try? Data(contentsOf: profileImageURL) else {
            profileImage = nil
            return
        }
        profileImage = UIImage(data: data)
    }
}

private enum ProfileSignInError: LocalizedError {
    case missingGamertag

    var errorDescription: String? {
        switch self {
        case .missingGamertag:
            return "Enter a gamertag to continue."
        }
    }
}

private struct DocumentImportPicker: UIViewControllerRepresentable {
    let target: ImportTarget
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: target.allowedTypes,
            asCopy: true
        )
        controller.allowsMultipleSelection = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

private struct AssetRow: View {
    let title: String
    let file: LibraryFile?
    let missingSystemImage: String
    let missingText: String

    init(title: String, file: LibraryFile?, missingSystemImage: String, missingText: String = "Missing") {
        self.title = title
        self.file = file
        self.missingSystemImage = missingSystemImage
        self.missingText = missingText
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file == nil ? missingSystemImage : "checkmark.circle.fill")
                .foregroundStyle(file == nil ? Color.secondary : Color.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(file?.displayName ?? missingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let file {
                Text(file.byteCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct GameRow: View {
    let game: LibraryFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName)
                    .lineLimit(1)
                Text(game.byteCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct EmptyStateRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}

private struct CoreStatusRow: View {
    let state: EmulatorCoreRuntime.RunState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44)
    }

    private var title: String {
        switch state {
        case .ready:
            return "Core Ready"
        case .running:
            return "Core Running"
        case .exited:
            return "Core Exited"
        case .failed:
            return "Core Failed"
        case .unavailable:
            return "Core Missing"
        }
    }

    private var detail: String {
        switch state {
        case .ready(let url):
            return url.lastPathComponent
        case .running(let game):
            return game
        case .exited(let status):
            return "Exit status \(status)"
        case .failed(let message), .unavailable(let message):
            return message
        }
    }

    private var systemImage: String {
        switch state {
        case .ready:
            return "checkmark.circle.fill"
        case .running:
            return "play.circle.fill"
        case .exited:
            return "stop.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "questionmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .ready:
            return .green
        case .running:
            return .accentColor
        case .exited:
            return .secondary
        case .failed:
            return .red
        case .unavailable:
            return .orange
        }
    }
}

private struct AutoJITStatusRow: View {
    let status: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == nil ? "link.circle" : "link.circle.fill")
                .foregroundStyle(status == nil ? Color.secondary : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("StikDebug")
                Text(status ?? "Ready for auto-enable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct FolderRow: View {
    let title: String
    let url: URL
    let storageUsed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Label(title, systemImage: "folder")
                Spacer()
                Text(storageUsed)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }
}

private enum CoverSelectionError: LocalizedError {
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "The selected image could not be loaded."
        }
    }
}

private enum AutoJITLaunchTarget: String {
    case dashboard
    case game

    var displayName: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .game:
            return "Game"
        }
    }
}

@MainActor
private final class StikDebugAutoJITCoordinator: ObservableObject {
    @Published private(set) var status: String?

    private static let pendingTargetKey = "AutoJITPendingLaunchTarget"
    private static let requestOpenedKey = "AutoJITRequestOpened"
    private static let didLeaveForStikDebugKey = "AutoJITDidLeaveForStikDebug"
    private static let returnedFromStikDebugAtKey = "AutoJITReturnedFromStikDebugAt"
    private static let requestedAtKey = "AutoJITRequestedAt"
    private static let suppressAutomaticDashboardLaunchUntilKey = "AutoJITSuppressAutomaticDashboardLaunchUntil"

    private static let pendingRequestTimeout: TimeInterval = 120
    private static let returnSettleDelay: TimeInterval = 6
    private static let automaticDashboardLaunchCooldown: TimeInterval = 45

    var hasPendingLaunch: Bool {
        pendingTarget != nil
    }

    var shouldSuppressAutomaticDashboardLaunch: Bool {
        Date().timeIntervalSince1970 <
            UserDefaults.standard.double(forKey: Self.suppressAutomaticDashboardLaunchUntilKey)
    }

    var hasObservedStikDebugTrip: Bool {
        UserDefaults.standard.bool(forKey: Self.didLeaveForStikDebugKey)
    }

    init() {
        clearStalePendingRequestIfNeeded()
    }

    func requestJIT(
        for target: AutoJITLaunchTarget,
        onFailure: @escaping (UserMessage) -> Void
    ) {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            onFailure(UserMessage(title: "Auto JIT Failed", detail: "The app bundle identifier is unavailable."))
            return
        }

        guard let url = makeStikDebugURL(bundleID: bundleID) else {
            onFailure(UserMessage(title: "Auto JIT Failed", detail: "Unable to create the StikDebug launch URL."))
            return
        }

        pendingTarget = target
        UserDefaults.standard.set(false, forKey: Self.requestOpenedKey)
        UserDefaults.standard.set(false, forKey: Self.didLeaveForStikDebugKey)
        UserDefaults.standard.removeObject(forKey: Self.returnedFromStikDebugAtKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.requestedAtKey)
        status = "Opening StikDebug for \(target.displayName)"

        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if success {
                    UserDefaults.standard.set(true, forKey: Self.requestOpenedKey)
                    self.status = "Waiting for StikDebug to return"
                } else {
                    self.clearPending()
                    onFailure(UserMessage(
                        title: "StikDebug Not Opened",
                        detail: "iOS could not open the stikjit://enable-jit URL. Confirm StikDebug is installed and closed before testing."
                    ))
                }
            }
        }
    }

    func markAppLeftForStikDebugIfPending() {
        guard hasPendingLaunch,
              UserDefaults.standard.bool(forKey: Self.requestOpenedKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.didLeaveForStikDebugKey)
        status = "StikDebug is enabling JIT"
    }

    func markAppReturnedFromStikDebugIfPending() {
        guard hasPendingLaunch,
              UserDefaults.standard.bool(forKey: Self.requestOpenedKey),
              UserDefaults.standard.bool(forKey: Self.didLeaveForStikDebugKey) else {
            return
        }
        guard UserDefaults.standard.double(forKey: Self.returnedFromStikDebugAtKey) == 0 else {
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: Self.returnedFromStikDebugAtKey)
        status = "Waiting for StikDebug to settle"
    }

    func noteAutomaticDashboardLaunchAttempt() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + Self.automaticDashboardLaunchCooldown,
                                  forKey: Self.suppressAutomaticDashboardLaunchUntilKey)
    }

    func clearPendingForFreshAutomaticLaunch() {
        clearPending()
        status = nil
    }

    func consumePendingLaunchIfReady() -> AutoJITLaunchTarget? {
        guard let target = pendingTarget else {
            return nil
        }
        guard UserDefaults.standard.bool(forKey: Self.requestOpenedKey) else {
            return nil
        }
        guard UserDefaults.standard.bool(forKey: Self.didLeaveForStikDebugKey) else {
            return nil
        }

        let returnedAt = UserDefaults.standard.double(forKey: Self.returnedFromStikDebugAtKey)
        guard returnedAt > 0,
              Date().timeIntervalSince1970 - returnedAt > Self.returnSettleDelay else {
            return nil
        }

        clearPending()
        status = "Launching \(target.displayName) after JIT"
        return target
    }

    func forcePendingLaunchReady() {
        guard hasPendingLaunch else {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.requestOpenedKey)
        UserDefaults.standard.set(true, forKey: Self.didLeaveForStikDebugKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970 - Self.returnSettleDelay - 1,
                                  forKey: Self.returnedFromStikDebugAtKey)
        status = "Launching after StikDebug timeout"
    }

    private var pendingTarget: AutoJITLaunchTarget? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Self.pendingTargetKey) else {
                return nil
            }
            return AutoJITLaunchTarget(rawValue: rawValue)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.pendingTargetKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingTargetKey)
            }
        }
    }

    private func clearPending() {
        pendingTarget = nil
        UserDefaults.standard.removeObject(forKey: Self.requestOpenedKey)
        UserDefaults.standard.removeObject(forKey: Self.didLeaveForStikDebugKey)
        UserDefaults.standard.removeObject(forKey: Self.returnedFromStikDebugAtKey)
        UserDefaults.standard.removeObject(forKey: Self.requestedAtKey)
    }

    private func clearStalePendingRequestIfNeeded() {
        guard pendingTarget != nil else {
            return
        }

        let requestedAt = UserDefaults.standard.double(forKey: Self.requestedAtKey)
        guard requestedAt == 0 ||
              Date().timeIntervalSince1970 - requestedAt > Self.pendingRequestTimeout else {
            return
        }

        clearPending()
    }

    private func makeStikDebugURL(bundleID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "stikjit"
        components.host = "enable-jit"
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundleID),
            URLQueryItem(name: "script-name", value: "Universal.js")
        ]
        return components.url
    }
}

private struct LaunchPlanView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: XemuLaunchPlan

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    Label(plan.gameName, systemImage: "opticaldisc")
                }

                Section("JIT") {
                    Label(plan.universalJITEnabled ? "Universal.js" : "Disabled",
                          systemImage: plan.universalJITEnabled ? "bolt.horizontal.circle.fill" : "bolt.slash")
                }

                Section("Config") {
                    Text(plan.configURL.lastPathComponent)
                    Text(plan.configURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Arguments") {
                    Text(plan.commandLine)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Launch Ready")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
