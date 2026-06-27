import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EmulatorFileStore
    @ObservedObject var profileStore: InsigniaProfileStore
    let runtimeState: EmulatorCoreRuntime.RunState
    let importSystemFiles: () -> Void
    @State private var lilyDedicationTapCount = 0
    @State private var lastLilyDedicationTapDate: Date?
    @State private var lilyDedicationJiggleAngle = 0.0
    @State private var lilyDedicationJiggleOffset: CGFloat = 0
    @State private var isCloudSaveOperationRunning = false

    var body: some View {
        List {
            Section("Runtime") {
                #if targetEnvironment(macCatalyst) || os(macOS)
                DesktopRuntimeSettingsView(store: store, runtimeState: runtimeState)
                #else
                Toggle(isOn: $store.universalJITEnabled) {
                    Label("Universal.js JIT", systemImage: "bolt.horizontal.circle")
                }

                Text("Required on iOS 26 or later. iOS 16 through 18 use W^X reprotection after JIT is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.autoJITBeforeLaunchEnabled) {
                    Label("Auto-enable via StikDebug", systemImage: "arrow.triangle.2.circlepath")
                }

                Text("Automatically enables the active JIT path before launching a game.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.autoLaunchDashboardOnOpenEnabled) {
                    Label("Auto Launch Dashboard", systemImage: "rectangle.grid.1x2.fill")
                }

                Text("Recommended only if you use XBMC or another replacement dashboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                CoreStatusRow(state: runtimeState)
                #endif
            }
            .dukeXThemedListRowBackground()

            #if !targetEnvironment(macCatalyst) && !os(macOS)
            Section("Display") {
                Toggle(isOn: $store.metalHUDEnabled) {
                    Label("Metal HUD", systemImage: "gauge.with.dots.needle.67percent")
                }

                Text("Off by default. Changes apply the next time the emulator view starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.forceThirtyFPSLockEnabled) {
                    Label("Lock Gameplay to 30 FPS", systemImage: "30.circle")
                }

                Text("Forces 30 FPS FIFO pacing while the emulator is running. Changes apply on the next launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $store.depthClampEnabled) {
                    Label("Depth Clamp", systemImage: "square.stack.3d.down.forward")
                }

                Text("Clamps guest shader depth on iOS instead of discarding fragments outside the guest clip range. Changes apply on the next launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Display Sync", systemImage: "display")
                    Text("Default Accurate. Controls display synchronization and frame presentation timing; Accurate uses FIFO with display sync for the most compatible output. Changes apply on the next launch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker(selection: $store.presentPacingMode) {
                    ForEach(PresentPacingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text("Display Sync")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(store.presentPacingMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dukeXThemedListRowBackground()

            Section("Peripherals") {
                Toggle(isOn: $store.xboxHeadsetMicPeripheralEnabled) {
                    Label("Xbox Live Communicator", systemImage: "mic.circle")
                }

                Text("Experimental. Attaches an Xbox Live Communicator on launch and routes the iPhone microphone through it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(isOn: .constant(false)) {
                    Label("Xbox Video Chat Camera", systemImage: "video.circle")
                }
                .disabled(true)

                Text("Experimental. Attaches an Xbox Video Chat camera on launch and routes the iPhone face camera through it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dukeXThemedListRowBackground()
            #endif

            Section("Themes") {
                ThemeSettingsView(store: store)
            }
            .dukeXThemedListRowBackground()

            #if !targetEnvironment(macCatalyst) && !os(macOS)
            Section("Touch Controls") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Haptic Feedback", systemImage: "hand.tap")
                    Text("Default Medium. Adjusts haptic feedback intensity to preference.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker(selection: $store.touchHapticFeedbackLevel) {
                    ForEach(TouchHapticFeedbackLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                } label: {
                    Text("Haptic Feedback")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: store.touchHapticFeedbackLevel) { level in
                    TouchHapticFeedbackPerformer.shared.play(level: level)
                }

                NavigationLink {
                    SkinAssignmentView(store: store)
                } label: {
                    SkinAssignmentSummaryRow(selectedSkinName: store.selectedSkinSummaryText,
                                             skinCount: store.skins.count)
                }
            }
            .dukeXThemedListRowBackground()
            #endif

            Section("Library") {
                LibraryColumnSettingsView(store: store)
            }
            .dukeXThemedListRowBackground()

            #if !targetEnvironment(macCatalyst) && !os(macOS)
            Section("Advanced") {
                Picker(selection: $store.tbCacheSize) {
                    ForEach(TBCacheSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                } label: {
                    Label("TB Cache Size", systemImage: "memorychip")
                }
                .pickerStyle(.segmented)

                Text("Controls the JIT translated block cache. 64 MB is the current default; changes apply on the next launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dukeXThemedListRowBackground()
            #endif

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

                Group {
                    Toggle(isOn: $store.cloudSaveSyncEnabled) {
                        Label("Cloud Sync Saves", systemImage: "icloud")
                    }

                    Text("Experimental. Off by default. Uses xb.live services to sync your save files automatically across your physical Xbox hardware, DukeX, and other compatible emulators.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(action: pushSavesToCloud) {
                        CloudSaveActionLabel(
                            title: "Push Saves to Cloud",
                            detail: "Manually uploads the latest saves from the Xbox HDD to xb.live.",
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: pullSavesFromCloud) {
                        CloudSaveActionLabel(
                            title: "Pull Saves from Cloud",
                            detail: "Manually downloads cloud saves and imports missing titles into the Xbox HDD.",
                            systemImage: "icloud.and.arrow.down"
                        )
                    }
                    .buttonStyle(.plain)

                    if isCloudSaveOperationRunning {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Syncing saves...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 36)
                    }
                }
                .disabled(!cloudSaveControlsEnabled || isCloudSaveOperationRunning)
                .opacity(cloudSaveControlsEnabled ? 1 : 0.45)
            }
            .dukeXThemedListRowBackground()

            Section("System Files") {
                AssetRow(title: "Flash BIOS", file: store.bios, missingSystemImage: "memorychip")
                AssetRow(title: "MCPX", file: store.mcpx, missingSystemImage: "lock.rectangle")
                AssetRow(title: "EEPROM", file: store.eeprom, missingSystemImage: "key", missingText: "Generated automatically")
                AssetRow(title: "HDD", file: store.hdd, missingSystemImage: "internaldrive")

                Button(action: importSystemFiles) {
                    Label("Import System Files", systemImage: "tray.and.arrow.down")
                }
            }
            .dukeXThemedListRowBackground()

            Section("Communities") {
                CommunityLinkRow(
                    title: "Manic EMU & DukeX Official Discord",
                    detail: "Join the official Manic EMU and DukeX community for support, troubleshooting, updates, and emulator discussion.",
                    imageName: "ManicDukeXCommunityIcon",
                    glyphSize: 40,
                    url: URL(string: "https://discord.gg/manicemu")!
                )

                CommunityLinkRow(
                    title: "XBL: OG Xbox Live Discord",
                    detail: "Find players, events, and help for the xb.live services used by DukeX online play.",
                    imageName: "XBLCommunityIcon",
                    glyphSize: 36,
                    url: URL(string: "https://discord.gg/xbl")!,
                    beforeOpen: {
                        store.unlockLivingOriginalTheme()
                    }
                )
            }
            .dukeXThemedListRowBackground()

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
                .offset(x: lilyDedicationJiggleOffset)
                .rotationEffect(.degrees(lilyDedicationJiggleAngle))
                .contentShape(Rectangle())
                .onTapGesture {
                    handleLilyDedicationTap()
                }
            }
            .dukeXThemedListRowBackground()
        }
        .dukeXThemedListBackground()
    }

    private func handleLilyDedicationTap() {
        triggerLilyDedicationJiggle()

        guard !store.alwaysRememberedThemeUnlocked else {
            return
        }

        let now = Date()
        if let lastLilyDedicationTapDate,
           now.timeIntervalSince(lastLilyDedicationTapDate) <= 2.0 {
            lilyDedicationTapCount += 1
        } else {
            lilyDedicationTapCount = 1
        }
        self.lastLilyDedicationTapDate = now

        if lilyDedicationTapCount >= 3 {
            store.unlockAlwaysRememberedTheme()
            lilyDedicationTapCount = 0
            lastLilyDedicationTapDate = nil
        }
    }

    private func triggerLilyDedicationJiggle() {
        Task { @MainActor in
            let steps: [(angle: Double, offset: CGFloat, duration: UInt64)] = [
                (-0.8, -1.4, 55_000_000),
                (0.8, 1.4, 70_000_000),
                (-0.4, -0.7, 55_000_000),
                (0.0, 0.0, 80_000_000)
            ]

            for step in steps {
                withAnimation(.easeInOut(duration: Double(step.duration) / 1_000_000_000)) {
                    lilyDedicationJiggleAngle = step.angle
                    lilyDedicationJiggleOffset = step.offset
                }
                try? await Task.sleep(nanoseconds: step.duration)
            }
        }
    }

    private var cloudSaveControlsEnabled: Bool {
        profileStore.isAuthenticatedForCloudServices && !isRuntimeUsingHDD
    }

    private var isRuntimeUsingHDD: Bool {
        if case .running = runtimeState {
            return true
        }
        return false
    }

    private func pushSavesToCloud() {
        do {
            try store.prepareCloudSaveDirectory()
        } catch {
            store.message = UserMessage(title: "Cloud Save Sync Failed", detail: error.localizedDescription)
            return
        }

        let directoryURL = store.cloudSavesDirectoryURL
        let games = store.games
        let hdd = store.hdd
        let eeprom = store.eeprom
        runCloudSaveOperation(successTitle: "Saves Pushed") { sessionKey in
            let result = try await XBLCloudSaveService().pushLocalSaves(
                sessionKey: sessionKey,
                hdd: hdd,
                eeprom: eeprom,
                cloudSavesDirectoryURL: directoryURL,
                games: games
            )
            return result.pushDetail
        }
    }

    private func pullSavesFromCloud() {
        do {
            try store.prepareCloudSaveDirectory()
        } catch {
            store.message = UserMessage(title: "Cloud Save Sync Failed", detail: error.localizedDescription)
            return
        }

        let directoryURL = store.cloudSavesDirectoryURL
        let hdd = store.hdd
        let eeprom = store.eeprom
        runCloudSaveOperation(successTitle: "Saves Pulled") { sessionKey in
            let result = try await XBLCloudSaveService().pullRemoteSaves(
                sessionKey: sessionKey,
                hdd: hdd,
                eeprom: eeprom,
                cloudSavesDirectoryURL: directoryURL
            )
            return result.pullDetail
        }
    }

    private func runCloudSaveOperation(
        successTitle: String,
        operation: @escaping (String) async throws -> String
    ) {
        guard cloudSaveControlsEnabled else {
            if isRuntimeUsingHDD {
                store.message = UserMessage(
                    title: "Cloud Saves Unavailable",
                    detail: "Stop the emulator before syncing saves so DukeX can safely read and write the Xbox HDD."
                )
            } else {
                store.message = UserMessage(
                    title: "Sign In Required",
                    detail: "Sign in with an xb.live account in the Profile tab to use cloud saves."
                )
            }
            return
        }
        guard !isCloudSaveOperationRunning else {
            return
        }

        isCloudSaveOperationRunning = true
        Task {
            do {
                guard let sessionKey = try InsigniaProfileStore.storedSessionKey(),
                      !sessionKey.isEmpty else {
                    throw CloudSaveSettingsError.missingSession
                }

                let detail = try await operation(sessionKey)
                await MainActor.run {
                    store.message = UserMessage(title: successTitle, detail: detail)
                    isCloudSaveOperationRunning = false
                }
            } catch {
                await MainActor.run {
                    store.message = UserMessage(title: "Cloud Save Sync Failed", detail: error.localizedDescription)
                    isCloudSaveOperationRunning = false
                }
            }
        }
    }
}

private enum CloudSaveSettingsError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "The xb.live session is missing. Sign out and sign in again from the Profile tab."
        }
    }
}

private struct DesktopRuntimeSettingsView: View {
    @ObservedObject var store: EmulatorFileStore
    let runtimeState: EmulatorCoreRuntime.RunState

    var body: some View {
        CoreStatusRow(state: runtimeState)

        Toggle(isOn: $store.autoLaunchDashboardOnOpenEnabled) {
            Label("Auto Launch Dashboard", systemImage: "rectangle.grid.1x2.fill")
        }

        Text("Starts Xemu directly into the Xbox dashboard when DukeX opens.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 4) {
            Label("Renderer", systemImage: "display")
            Text(store.desktopRendererBackend.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Picker(selection: $store.desktopRendererBackend) {
            ForEach(DesktopRendererBackend.allCases) { renderer in
                Text(renderer.title).tag(renderer)
            }
        } label: {
            Text("Renderer")
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        VStack(alignment: .leading, spacing: 4) {
            Label("Game Resolution", systemImage: "rectangle.expand.vertical")
            Text(store.desktopGameResolutionScale.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Picker(selection: $store.desktopGameResolutionScale) {
            ForEach(DesktopGameResolutionScale.allCases) { scale in
                Text(scale.title).tag(scale)
            }
        } label: {
            Label("Internal Resolution Scale", systemImage: "rectangle.expand.vertical")
        }
        .pickerStyle(.menu)

        VStack(alignment: .leading, spacing: 4) {
            Label("Aspect Ratio", systemImage: "rectangle.inset.filled")
            Text(store.desktopDisplayAspectRatio.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Picker(selection: $store.desktopDisplayAspectRatio) {
            ForEach(DesktopDisplayAspectRatio.allCases) { aspectRatio in
                Text(aspectRatio.title).tag(aspectRatio)
            }
        } label: {
            Text("Aspect Ratio")
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        VStack(alignment: .leading, spacing: 4) {
            Label("Acceleration", systemImage: "speedometer")
            Text(store.desktopAccelerationMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Picker(selection: $store.desktopAccelerationMode) {
            ForEach(DesktopAccelerationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            Text("Acceleration")
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if store.desktopAccelerationMode == .tcgMultiThread {
            Picker(selection: $store.tbCacheSize) {
                ForEach(TBCacheSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            } label: {
                Label("TCG Cache Size", systemImage: "memorychip")
            }
            .pickerStyle(.segmented)

            Text("Applies only when the Xemu accelerator is set to TCG.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Toggle(isOn: $store.xemuShaderCacheEnabled) {
            Label("Shader Cache", systemImage: "square.stack.3d.up")
        }

        Text("Keeps Xemu's shader cache enabled across launches.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Toggle(isOn: $store.xemuBackgroundInputCaptureEnabled) {
            Label("Background Input Capture", systemImage: "gamecontroller")
        }

        Toggle(isOn: $store.xemuHideCursorEnabled) {
            Label("Hide Cursor During Gameplay", systemImage: "cursorarrow.slash")
        }

        Toggle(isOn: $store.xemuShowMenubarEnabled) {
            Label("Show Xemu Menu Bar", systemImage: "menubar.rectangle")
        }

        VStack(alignment: .leading, spacing: 4) {
            Label("Xemu Config", systemImage: "doc.text")
            Text(store.documentsURL.appendingPathComponent("xemu-desktop.toml").path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }

        VStack(alignment: .leading, spacing: 4) {
            Label("Shader Cache Folder", systemImage: "folder")
            Text(store.shaderCachesDirectoryURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct CloudSaveActionLabel: View {
    @Environment(\.dukeXTheme) private var theme

    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(theme.accentColor)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
