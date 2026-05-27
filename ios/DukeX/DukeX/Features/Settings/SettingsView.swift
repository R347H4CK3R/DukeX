import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EmulatorFileStore
    let runtimeState: EmulatorCoreRuntime.RunState
    let autoJITStatus: String?
    let importSystemFiles: () -> Void

    var body: some View {
        List {
            Section("Runtime") {
                Toggle(isOn: $store.universalJITEnabled) {
                    Label("Universal.js JIT", systemImage: "bolt.horizontal.circle")
                }

                Text("Required on iOS 26 or later. iOS 18.x uses W^X reprotection after JIT is enabled.")
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
                AutoJITStatusRow(status: autoJITStatus)
            }

            Section("Display") {
                Toggle(isOn: $store.statsHUDEnabled) {
                    Label("Stats HUD", systemImage: "waveform.path.ecg.rectangle")
                }

                Text("Shows FPS, CPU, memory, and thermal state while a game is running.")
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

                Text("Experimental. Attaches an Xbox Video Chat camera on launch and routes the iPhone face camera through it. Coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }

            Section("Library") {
                LibraryColumnSettingsView(store: store)
            }

            Section("Advanced") {
                Picker(selection: $store.tbCacheSize) {
                    ForEach(TBCacheSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                } label: {
                    Label("TB Cache Size", systemImage: "memorychip")
                }
                .pickerStyle(.segmented)

                Text("Controls the JIT translated block cache. 128 MB is the current default; changes apply on the next launch.")
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

                Button(action: importSystemFiles) {
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
}
