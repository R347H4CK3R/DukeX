import Foundation
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryFile: Identifiable, Equatable {
    enum Kind {
        case bios
        case mcpx
        case eeprom
        case hdd
        case game
        case unknown
    }

    let url: URL
    let size: Int64
    let kind: Kind
    let titleName: String?
    let coverURL: URL?
    let customConfigURL: URL?

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
    var fallbackDisplayName: String {
        kind == .game ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }
    var displayName: String {
        if kind == .game, let titleName, !titleName.isEmpty {
            return titleName
        }
        return fallbackDisplayName
    }
    var byteCount: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

enum ImportTarget: String, Identifiable {
    case systemFiles
    case games

    var id: String { rawValue }

    var allowedTypes: [UTType] {
        switch self {
        case .systemFiles:
            return [
                UTType(filenameExtension: "bin"),
                UTType(filenameExtension: "qcow2"),
                UTType(filenameExtension: "qcow"),
                UTType(filenameExtension: "img"),
                UTType(filenameExtension: "raw"),
                UTType(filenameExtension: "hdd"),
                .data
            ].compactMap { $0 }
        case .games:
            return [
                UTType(filenameExtension: "xiso"),
                UTType(filenameExtension: "iso"),
                .diskImage,
                .data,
                .item
            ].compactMap { $0 }
        }
    }
}

struct UserMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct FolderStorageUsage: Equatable {
    struct Folder: Equatable {
        static let zero = Folder(byteCount: 0)

        let byteCount: Int64

        var displayText: String {
            ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        }
    }

    static let empty = FolderStorageUsage(bios: .zero, roms: .zero, covers: .zero)

    let bios: Folder
    let roms: Folder
    let covers: Folder
}

struct NetworkSettings {
    static let insigniaDNSServer = "46.101.64.175"
    static let defaultHostPort = "3074"
    static let defaultGuestPort = "3074"
    static let defaultProtocol = "udp"

    let forceInsigniaNAT: Bool
    let insigniaPacketCapture: Bool
    let dnsServer: String
    let hostPort: String
    let guestPort: String
    let portProtocol: String

    var effectiveDNSServer: String? {
        if forceInsigniaNAT {
            return Self.insigniaDNSServer
        }

        let trimmed = dnsServer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var effectiveHostPort: Int {
        Self.portValue(hostPort, fallback: Int(Self.defaultHostPort) ?? 3074)
    }

    var effectiveGuestPort: Int {
        Self.portValue(guestPort, fallback: Int(Self.defaultGuestPort) ?? 3074)
    }

    var effectivePortProtocol: String {
        let normalized = portProtocol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "tcp" ? "tcp" : "udp"
    }

    private static func portValue(_ value: String, fallback: Int) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65_535).contains(port) else {
            return fallback
        }
        return port
    }
}

enum PresentPacingMode: String, CaseIterable, Identifiable {
    case speed
    case smooth
    case accurate

    var id: String { rawValue }

    static let defaultsKey = "PresentPacingMode"

    static var current: PresentPacingMode {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? PresentPacingMode.speed.rawValue
        return PresentPacingMode(rawValue: rawValue) ?? .speed
    }

    var title: String {
        switch self {
        case .speed:
            return "Speed"
        case .smooth:
            return "Smooth"
        case .accurate:
            return "Accurate"
        }
    }

    var detail: String {
        switch self {
        case .speed:
            return "Immediate present, display sync off."
        case .smooth:
            return "Mailbox present, display sync off."
        case .accurate:
            return "FIFO present, display sync on."
        }
    }

    var vulkanPresentMode: String {
        switch self {
        case .speed:
            return "immediate"
        case .smooth:
            return "mailbox"
        case .accurate:
            return "fifo"
        }
    }

    var presentFPS: String {
        switch self {
        case .speed, .smooth:
            return "0"
        case .accurate:
            return "60"
        }
    }

    var displaySyncEnabled: Bool {
        self == .accurate
    }

    var nominalFramesPerSecondValue: Int {
        switch self {
        case .speed, .smooth:
            return 120
        case .accurate:
            return 60
        }
    }

    var nominalFramesPerSecond: String {
        String(nominalFramesPerSecondValue)
    }
}

enum TBCacheSize: Int, CaseIterable, Identifiable {
    case mb64 = 64
    case mb128 = 128
    case mb256 = 256

    var id: Int { rawValue }

    static let defaultsKey = "DukeXTBCacheSizeMB"

    static var current: TBCacheSize {
        let storedValue = UserDefaults.standard.integer(forKey: defaultsKey)
        return TBCacheSize(rawValue: storedValue) ?? .mb128
    }

    var title: String {
        "\(rawValue) MB"
    }

    var launchArgumentValue: String {
        String(rawValue)
    }
}

@MainActor
final class EmulatorFileStore: ObservableObject {
    @Published private(set) var bios: LibraryFile?
    @Published private(set) var mcpx: LibraryFile?
    @Published private(set) var eeprom: LibraryFile?
    @Published private(set) var hdd: LibraryFile?
    @Published private(set) var games: [LibraryFile] = []
    @Published var selectedGameID = "" {
        didSet {
            UserDefaults.standard.set(selectedGameID, forKey: Self.selectedGameIDKey)
            if let selectedGame {
                UserDefaults.standard.set(selectedGame.fileName, forKey: Self.selectedGameNameKey)
            }
        }
    }
    @Published var universalJITEnabled: Bool {
        didSet {
            UserDefaults.standard.set(universalJITEnabled, forKey: Self.universalJITKey)
            setenv("XEMU_IOS_UNIVERSAL_JIT", universalJITEnabled ? "1" : "0", 1)
        }
    }
    @Published var autoJITBeforeLaunchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoJITBeforeLaunchEnabled, forKey: Self.autoJITBeforeLaunchKey)
        }
    }
    @Published var autoLaunchDashboardOnOpenEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoLaunchDashboardOnOpenEnabled, forKey: Self.autoLaunchDashboardOnOpenKey)
        }
    }
    @Published var presentPacingMode: PresentPacingMode {
        didSet {
            UserDefaults.standard.set(presentPacingMode.rawValue, forKey: PresentPacingMode.defaultsKey)
        }
    }
    @Published var metalHUDEnabled: Bool {
        didSet {
            UserDefaults.standard.set(metalHUDEnabled, forKey: Self.metalHUDEnabledKey)
            MetalDiagnostics.configurePerformanceHUD()
        }
    }
    @Published var statsHUDEnabled: Bool {
        didSet {
            UserDefaults.standard.set(statsHUDEnabled, forKey: Self.statsHUDEnabledKey)
        }
    }
    @Published var forceThirtyFPSLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(forceThirtyFPSLockEnabled, forKey: Self.forceThirtyFPSLockEnabledKey)
        }
    }
    @Published var tbCacheSize: TBCacheSize {
        didSet {
            UserDefaults.standard.set(tbCacheSize.rawValue, forKey: TBCacheSize.defaultsKey)
        }
    }
    @Published var forceInsigniaNATEnabled: Bool {
        didSet {
            UserDefaults.standard.set(forceInsigniaNATEnabled, forKey: Self.forceInsigniaNATKey)
        }
    }
    @Published var natDNSServer: String {
        didSet {
            UserDefaults.standard.set(natDNSServer, forKey: Self.natDNSServerKey)
        }
    }
    @Published var natHostPort: String {
        didSet {
            UserDefaults.standard.set(natHostPort, forKey: Self.natHostPortKey)
        }
    }
    @Published var natGuestPort: String {
        didSet {
            UserDefaults.standard.set(natGuestPort, forKey: Self.natGuestPortKey)
        }
    }
    @Published var natPortProtocol: String {
        didSet {
            UserDefaults.standard.set(natPortProtocol, forKey: Self.natPortProtocolKey)
        }
    }
    @Published var message: UserMessage?
    @Published var launchPlan: XemuLaunchPlan?
    @Published private(set) var folderStorageUsage = FolderStorageUsage.empty

    static let universalJITKey = "UniversalJITEnabled"
    static let autoJITBeforeLaunchKey = "AutoJITBeforeLaunchEnabled"
    static let autoLaunchDashboardOnOpenKey = "AutoLaunchDashboardOnOpenEnabled"
    static let libraryTabsMigrationKey = "LibraryTabsDisabledInitialDashboardAutolaunch"
    static let selectedGameIDKey = "SelectedGameID"
    static let selectedGameNameKey = "SelectedGameName"
    static let metalHUDEnabledKey = "DukeXMetalHUDEnabled"
    static let statsHUDEnabledKey = "DukeXStatsHUDEnabled"
    static let forceThirtyFPSLockEnabledKey = "DukeXForceThirtyFPSLockEnabled"
    static let forceInsigniaNATKey = "ForceInsigniaNATEnabled"
    static let natDNSServerKey = "NATDNSServer"
    static let natHostPortKey = "NATHostPort"
    static let natGuestPortKey = "NATGuestPort"
    static let natPortProtocolKey = "NATPortProtocol"

    let documentsURL: URL
    let biosDirectoryURL: URL
    let romsDirectoryURL: URL
    let coversDirectoryURL: URL
    let gameConfigsDirectoryURL: URL
    let shaderCachesDirectoryURL: URL

    var selectedGame: LibraryFile? {
        games.first { $0.id == selectedGameID }
    }

    var systemFilesReady: Bool {
        bios != nil && mcpx != nil && hdd != nil
    }

    var isReady: Bool {
        systemFilesReady && selectedGame != nil
    }

    var networkSettings: NetworkSettings {
        NetworkSettings(
            forceInsigniaNAT: forceInsigniaNATEnabled,
            insigniaPacketCapture: false,
            dnsServer: natDNSServer,
            hostPort: natHostPort,
            guestPort: natGuestPort,
            portProtocol: natPortProtocol
        )
    }

    init(fileManager: FileManager = .default) {
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        biosDirectoryURL = documentsURL.appendingPathComponent("BIOS", isDirectory: true)
        romsDirectoryURL = documentsURL.appendingPathComponent("ROMs", isDirectory: true)
        coversDirectoryURL = documentsURL.appendingPathComponent("Covers", isDirectory: true)
        gameConfigsDirectoryURL = documentsURL.appendingPathComponent("GameConfigs", isDirectory: true)
        shaderCachesDirectoryURL = documentsURL.appendingPathComponent("ShaderCaches", isDirectory: true)
        if UserDefaults.standard.object(forKey: Self.libraryTabsMigrationKey) == nil {
            UserDefaults.standard.set(false, forKey: Self.autoLaunchDashboardOnOpenKey)
            UserDefaults.standard.set(true, forKey: Self.libraryTabsMigrationKey)
        }
        universalJITEnabled = UserDefaults.standard.object(forKey: Self.universalJITKey) as? Bool ?? true
        autoJITBeforeLaunchEnabled = UserDefaults.standard.object(forKey: Self.autoJITBeforeLaunchKey) as? Bool ?? true
        autoLaunchDashboardOnOpenEnabled = UserDefaults.standard.object(forKey: Self.autoLaunchDashboardOnOpenKey) as? Bool ?? false
        presentPacingMode = PresentPacingMode.current
        metalHUDEnabled = UserDefaults.standard.object(forKey: Self.metalHUDEnabledKey) as? Bool ?? false
        statsHUDEnabled = UserDefaults.standard.object(forKey: Self.statsHUDEnabledKey) as? Bool ?? true
        forceThirtyFPSLockEnabled = UserDefaults.standard.object(forKey: Self.forceThirtyFPSLockEnabledKey) as? Bool ?? false
        tbCacheSize = TBCacheSize.current
        forceInsigniaNATEnabled = UserDefaults.standard.object(forKey: Self.forceInsigniaNATKey) as? Bool ?? true
        natDNSServer = UserDefaults.standard.string(forKey: Self.natDNSServerKey) ?? NetworkSettings.insigniaDNSServer
        natHostPort = UserDefaults.standard.string(forKey: Self.natHostPortKey) ?? NetworkSettings.defaultHostPort
        natGuestPort = UserDefaults.standard.string(forKey: Self.natGuestPortKey) ?? NetworkSettings.defaultGuestPort
        natPortProtocol = UserDefaults.standard.string(forKey: Self.natPortProtocolKey) ?? NetworkSettings.defaultProtocol
        selectedGameID = UserDefaults.standard.string(forKey: Self.selectedGameIDKey) ?? ""
        setenv("XEMU_IOS_UNIVERSAL_JIT", universalJITEnabled ? "1" : "0", 1)
    }

    func prepareAndRefresh() async {
        do {
            try prepareDirectories()
            try refresh()
        } catch {
            message = UserMessage(title: "Library Error", detail: error.localizedDescription)
        }
    }

    func refresh() throws {
        try prepareDirectories()
        let systemFiles = try scanDirectory(biosDirectoryURL)
        let gameFiles = try scanDirectory(romsDirectoryURL)
        let coverFiles = try scanDirectory(coversDirectoryURL)

        folderStorageUsage = FolderStorageUsage(
            bios: FolderStorageUsage.Folder(byteCount: totalSize(of: systemFiles)),
            roms: FolderStorageUsage.Folder(byteCount: totalSize(of: gameFiles)),
            covers: FolderStorageUsage.Folder(byteCount: totalSize(of: coverFiles))
        )

        mcpx = systemFiles
            .filter { $0.url.pathExtension.caseInsensitiveCompare("bin") == .orderedSame && $0.size == 512 }
            .sorted(by: sortByName)
            .first

        eeprom = systemFiles
            .filter { $0.url.pathExtension.caseInsensitiveCompare("bin") == .orderedSame && $0.size == 256 }
            .sorted(by: sortByName)
            .first

        bios = systemFiles
            .filter { file in
                file.url.pathExtension.caseInsensitiveCompare("bin") == .orderedSame &&
                file.size > 512 &&
                file.size % 65_536 == 0
            }
            .sorted(by: sortByName)
            .first

        hdd = systemFiles
            .filter { isHDD($0) }
            .sorted(by: sortByName)
            .first

        games = gameFiles
            .filter { isGame($0) }
            .map { makeGameLibraryFile(from: $0) }
            .sorted(by: sortByName)

        if selectedGame == nil {
            let selectedName = UserDefaults.standard.string(forKey: Self.selectedGameNameKey)
            if let selectedName,
               let matchingGame = games.first(where: { $0.fileName == selectedName }) {
                selectedGameID = matchingGame.id
            } else {
                selectedGameID = games.first?.id ?? ""
            }
        }
    }

    func importFiles(_ urls: [URL], to target: ImportTarget) {
        do {
            let destinationDirectory = target == .systemFiles ? biosDirectoryURL : romsDirectoryURL
            try prepareDirectories()

            for url in urls {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let destination = destinationDirectory.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            }

            try refresh()
        } catch {
            message = UserMessage(title: "Import Failed", detail: error.localizedDescription)
        }
    }

    func prepareLaunchPlan() {
        do {
            launchPlan = try makeLaunchPlan()
        } catch {
            message = UserMessage(title: "Launch Blocked", detail: error.localizedDescription)
        }
    }

    func makeLaunchPlan() throws -> XemuLaunchPlan {
        let systemFiles = try makeSystemFileSet()
        guard let selectedGame else {
            throw LaunchPlanError.missing("Game")
        }

        return try XemuLaunchPlan.make(
            documentsURL: documentsURL,
            bios: systemFiles.bios,
            mcpx: systemFiles.mcpx,
            eeprom: systemFiles.eeprom,
            hdd: systemFiles.hdd,
            game: selectedGame,
            gamesDirectoryURL: romsDirectoryURL,
            universalJITEnabled: universalJITEnabled,
            networkSettings: networkSettings,
            tbCacheSize: tbCacheSize,
            shaderCacheURL: shaderCacheURL(for: selectedGame)
        )
    }

    func makeDashboardLaunchPlan() throws -> XemuLaunchPlan {
        let systemFiles = try makeSystemFileSet()

        return try XemuLaunchPlan.make(
            documentsURL: documentsURL,
            bios: systemFiles.bios,
            mcpx: systemFiles.mcpx,
            eeprom: systemFiles.eeprom,
            hdd: systemFiles.hdd,
            game: nil,
            gamesDirectoryURL: romsDirectoryURL,
            universalJITEnabled: universalJITEnabled,
            networkSettings: networkSettings,
            tbCacheSize: tbCacheSize,
            shaderCacheURL: dashboardShaderCacheURL
        )
    }

    func assignCover(_ data: Data, to game: LibraryFile) throws {
        try prepareDirectories()
        let imageData = UIImage(data: data)?.jpegData(compressionQuality: 0.92) ?? data
        for destination in coverWriteURLs(for: game) {
            try imageData.write(to: destination, options: .atomic)
        }
        try refresh()
    }

    func importCustomConfig(_ url: URL, for game: LibraryFile) throws {
        try prepareDirectories()

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = customConfigURL(for: game)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        try refresh()
    }

    func clearShaderCache(for game: LibraryFile) throws {
        let url = shaderCacheURL(for: game)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        message = UserMessage(
            title: "Shader Cache Cleared",
            detail: "\(game.displayName)'s shader cache will be rebuilt next time it launches."
        )
    }

    func removeGame(_ game: LibraryFile) throws {
        let urls = [
            game.url,
            coverURL(for: game),
            portableCoverURL(for: game),
            legacyCoverURL(forGameURL: game.url),
            customConfigURL(for: game),
            legacyCustomConfigURL(forGameURL: game.url),
            shaderCacheURL(for: game)
        ]

        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        if selectedGameID == game.id {
            selectedGameID = ""
            UserDefaults.standard.removeObject(forKey: Self.selectedGameNameKey)
        }

        try refresh()
    }

    private func makeSystemFileSet() throws -> (bios: LibraryFile, mcpx: LibraryFile, eeprom: LibraryFile?, hdd: LibraryFile) {
        guard let bios else {
            throw LaunchPlanError.missing("Flash BIOS")
        }
        guard let mcpx else {
            throw LaunchPlanError.missing("MCPX")
        }
        guard let hdd else {
            throw LaunchPlanError.missing("HDD")
        }
        return (bios, mcpx, eeprom, hdd)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: biosDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: romsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: gameConfigsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: shaderCachesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func scanDirectory(_ url: URL) throws -> [LibraryFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { fileURL in
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                return nil
            }
            let size = Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            return LibraryFile(url: fileURL, size: size, kind: .unknown, titleName: nil, coverURL: nil, customConfigURL: nil)
        }
    }

    private func makeGameLibraryFile(from file: LibraryFile) -> LibraryFile {
        let title = XISOGameTitleReader.titleName(in: file.url)
        let cover = existingCoverURL(for: file.url, titleName: title, size: file.size)
        let customConfig = existingCustomConfigURL(for: file.url, titleName: title, size: file.size)
        return LibraryFile(
            url: file.url,
            size: file.size,
            kind: .game,
            titleName: title,
            coverURL: cover,
            customConfigURL: customConfig
        )
    }

    private func isHDD(_ file: LibraryFile) -> Bool {
        let ext = file.url.pathExtension.lowercased()
        if ["qcow2", "qcow", "img", "raw", "hdd"].contains(ext) {
            return true
        }
        return ext == "bin" && file.size > 512 && file.id != bios?.id
    }

    private func isGame(_ file: LibraryFile) -> Bool {
        ["iso", "xiso"].contains(file.url.pathExtension.lowercased())
    }

    private func sortByName(_ lhs: LibraryFile, _ rhs: LibraryFile) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private func totalSize(of files: [LibraryFile]) -> Int64 {
        files.reduce(Int64(0)) { $0 + $1.size }
    }

    private func coverURL(for game: LibraryFile) -> URL {
        coverURL(forGameAssetID: gameAssetID(for: game))
    }

    private func coverURL(forGameAssetID assetID: String) -> URL {
        coversDirectoryURL.appendingPathComponent("cover-\(assetID).jpg")
    }

    private func portableCoverURL(for game: LibraryFile) -> URL {
        portableCoverURL(forGameURL: game.url)
    }

    private func portableCoverURL(forGameURL url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("cover.jpg")
    }

    private func legacyCoverURL(forGameURL url: URL) -> URL {
        coversDirectoryURL.appendingPathComponent("cover-\(Self.stableID(for: url.path)).jpg")
    }

    private func coverWriteURLs(for game: LibraryFile) -> [URL] {
        uniqueURLs([
            coverURL(for: game),
            portableCoverURL(for: game)
        ])
    }

    private func existingCoverURL(for gameURL: URL, titleName: String?, size: Int64) -> URL? {
        let portableURL = portableCoverURL(forGameURL: gameURL)
        if FileManager.default.fileExists(atPath: portableURL.path) {
            return portableURL
        }

        let canonicalURL = coverURL(forGameAssetID: gameAssetID(forGameURL: gameURL, titleName: titleName, size: size))
        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }

        let legacyURL = legacyCoverURL(forGameURL: gameURL)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }

        try? FileManager.default.copyItemIfNeeded(from: legacyURL, to: canonicalURL)
        try? FileManager.default.copyItemIfNeeded(from: legacyURL, to: portableURL)

        if FileManager.default.fileExists(atPath: portableURL.path) {
            return portableURL
        }
        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }
        return legacyURL
    }

    private func customConfigURL(for game: LibraryFile) -> URL {
        customConfigURL(forGameAssetID: gameAssetID(for: game))
    }

    private func customConfigURL(forGameAssetID assetID: String) -> URL {
        gameConfigsDirectoryURL.appendingPathComponent("config-\(assetID).toml")
    }

    private func legacyCustomConfigURL(forGameURL url: URL) -> URL {
        gameConfigsDirectoryURL.appendingPathComponent("config-\(Self.stableID(for: url.path)).toml")
    }

    private func existingCustomConfigURL(for gameURL: URL, titleName: String?, size: Int64) -> URL? {
        let canonicalURL = customConfigURL(forGameAssetID: gameAssetID(forGameURL: gameURL, titleName: titleName, size: size))
        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }

        let legacyURL = legacyCustomConfigURL(forGameURL: gameURL)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }

        try? FileManager.default.copyItemIfNeeded(from: legacyURL, to: canonicalURL)
        return FileManager.default.fileExists(atPath: canonicalURL.path) ? canonicalURL : legacyURL
    }

    private var dashboardShaderCacheURL: URL {
        shaderCachesDirectoryURL.appendingPathComponent("dashboard-vulkan-pipeline-cache.bin")
    }

    private func shaderCacheURL(for game: LibraryFile) -> URL {
        let url = shaderCachesDirectoryURL.appendingPathComponent("cache-\(gameAssetID(for: game))-vulkan-pipeline.bin")
        let legacyURL = shaderCachesDirectoryURL
            .appendingPathComponent("cache-\(Self.stableID(for: game.url.path))-vulkan-pipeline.bin")
        try? FileManager.default.copyItemIfNeeded(from: legacyURL, to: url)
        return url
    }

    private func gameAssetID(for game: LibraryFile) -> String {
        gameAssetID(forGameURL: game.url, titleName: game.titleName, size: game.size)
    }

    private func gameAssetID(forGameURL url: URL, titleName: String?, size: Int64) -> String {
        let normalizedTitle = Self.normalizedGameIdentityComponent(titleName)
        if !normalizedTitle.isEmpty {
            return Self.stableID(for: "title:\(normalizedTitle)|size:\(size)")
        }

        let relativePath = relativeGamePath(for: url) ?? url.lastPathComponent
        let normalizedPath = Self.normalizedGameIdentityComponent(relativePath)
        return Self.stableID(for: "file:\(normalizedPath)|size:\(size)")
    }

    private func relativeGamePath(for url: URL) -> String? {
        let basePath = romsDirectoryURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = basePath + "/"
        guard path.hasPrefix(prefix) else {
            return nil
        }
        return String(path.dropFirst(prefix.count))
    }

    private static func normalizedGameIdentityComponent(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private static func stableID(for string: String) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }
}

private enum XISOGameTitleReader {
    private static let sectorSize: UInt64 = 2_048
    private static let xboxMediaMagic = Data("MICROSOFT*XBOX*MEDIA".utf8)

    struct DirectoryEntry {
        let name: String
        let sector: UInt32
        let size: UInt32
    }

    struct VolumeDescriptor {
        let baseSector: UInt64
        let rootDirectorySector: UInt32
        let rootDirectorySize: UInt32
    }

    static func titleName(in url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            guard let descriptor = try findVolumeDescriptor(in: handle),
                  let defaultXBE = try findDefaultXBE(in: handle, descriptor: descriptor) else {
                return nil
            }

            let xbeOffset = (descriptor.baseSector + UInt64(defaultXBE.sector)) * sectorSize
            let xbeHeaders = try readXBEHeaders(
                from: handle,
                offset: xbeOffset,
                fileSize: Int(defaultXBE.size)
            )
            return titleName(fromXBEHeaders: xbeHeaders)
        } catch {
            return nil
        }
    }

    private static func findVolumeDescriptor(in handle: FileHandle) throws -> VolumeDescriptor? {
        if let descriptor = try readVolumeDescriptor(in: handle, sector: 32) {
            return descriptor
        }

        for sector in UInt64(0)..<512 where sector != 32 {
            if let descriptor = try readVolumeDescriptor(in: handle, sector: sector) {
                return descriptor
            }
        }

        return nil
    }

    private static func readVolumeDescriptor(in handle: FileHandle, sector: UInt64) throws -> VolumeDescriptor? {
        let data = try readData(from: handle, offset: sector * sectorSize, length: Int(sectorSize))
        guard data.count == Int(sectorSize) else {
            return nil
        }

        guard hasXboxMediaMagic(in: data),
              let rootSector = littleEndianUInt32(in: data, at: 20),
              let rootSize = littleEndianUInt32(in: data, at: 24),
              rootSector > 0,
              rootSize > 0,
              rootSize <= 16 * 1_024 * 1_024 else {
            return nil
        }

        return VolumeDescriptor(
            baseSector: sector >= 32 ? sector - 32 : 0,
            rootDirectorySector: rootSector,
            rootDirectorySize: rootSize
        )
    }

    private static func hasXboxMediaMagic(in data: Data) -> Bool {
        if data.starts(with: xboxMediaMagic) {
            return true
        }
        guard let trailerMagic = data[safeRange: 0x7EC..<(0x7EC + xboxMediaMagic.count)] else {
            return false
        }
        return trailerMagic == xboxMediaMagic
    }

    private static func findDefaultXBE(
        in handle: FileHandle,
        descriptor: VolumeDescriptor
    ) throws -> DirectoryEntry? {
        let rootOffset = (descriptor.baseSector + UInt64(descriptor.rootDirectorySector)) * sectorSize
        let rootLength = min(Int(descriptor.rootDirectorySize), 4 * 1_024 * 1_024)
        let data = try readData(from: handle, offset: rootOffset, length: rootLength)
        let entries = parseDirectoryEntries(data)

        return entries.first { entry in
            let name = entry.name.lowercased()
            return name == "default.xbe" || name == "default.xeb"
        }
    }

    private static func parseDirectoryEntries(_ data: Data) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        var offset = 0

        while offset + 14 <= data.count {
            guard let sector = littleEndianUInt32(in: data, at: offset + 4),
                  let size = littleEndianUInt32(in: data, at: offset + 8) else {
                break
            }

            let nameLength = Int(data[offset + 13])
            guard nameLength > 0, offset + 14 + nameLength <= data.count else {
                break
            }

            let nameData = data.subdata(in: (offset + 14)..<(offset + 14 + nameLength))
            if let name = String(data: nameData, encoding: .utf8) ??
                String(data: nameData, encoding: .ascii),
               !name.isEmpty {
                entries.append(DirectoryEntry(name: name, sector: sector, size: size))
            }

            let entryLength = (14 + nameLength + 3) & ~3
            guard entryLength > 0 else {
                break
            }
            offset += entryLength
        }

        return entries
    }

    private static func readXBEHeaders(
        from handle: FileHandle,
        offset: UInt64,
        fileSize: Int
    ) throws -> Data {
        let initialLength = min(max(fileSize, 0), 4_096)
        let initial = try readData(from: handle, offset: offset, length: initialLength)
        guard let headerSize = littleEndianUInt32(in: initial, at: 0x108),
              headerSize > 0,
              headerSize <= 512 * 1_024 else {
            return initial
        }

        let fullLength = min(Int(headerSize), max(fileSize, initial.count))
        guard fullLength > initial.count else {
            return initial
        }
        return try readData(from: handle, offset: offset, length: fullLength)
    }

    private static func titleName(fromXBEHeaders headers: Data) -> String? {
        guard littleEndianUInt32(in: headers, at: 0) == 0x4845_4258,
              let baseAddress = littleEndianUInt32(in: headers, at: 0x104),
              let certificateAddress = littleEndianUInt32(in: headers, at: 0x118) else {
            return nil
        }

        let candidateOffsets = [
            certificateOffset(certificateAddress, relativeTo: baseAddress),
            certificateOffset(certificateAddress, relativeTo: 0x0001_0000)
        ].compactMap { $0 }

        for certificateOffset in candidateOffsets where certificateOffset + 0x0C + 80 <= headers.count {
            let titleOffset = certificateOffset + 0x0C
            var units: [UInt16] = []

            for byteOffset in stride(from: titleOffset, to: titleOffset + 80, by: 2) {
                guard let value = littleEndianUInt16(in: headers, at: byteOffset),
                      value != 0 else {
                    break
                }
                units.append(value)
            }

            let title = String(decoding: units, as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }

        return nil
    }

    private static func certificateOffset(_ address: UInt32, relativeTo base: UInt32) -> Int? {
        guard address >= base else {
            return nil
        }
        return Int(address - base)
    }

    private static func readData(from handle: FileHandle, offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else {
            return Data()
        }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length) ?? Data()
    }

    private static func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else {
            return nil
        }

        return UInt16(data[offset]) |
            UInt16(data[offset + 1]) << 8
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else {
            return nil
        }

        return UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}

private extension Data {
    subscript(safeRange range: Range<Int>) -> Data? {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            return nil
        }
        return subdata(in: range)
    }
}

private extension FileManager {
    func copyItemIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        guard fileExists(atPath: sourceURL.path),
              !fileExists(atPath: destinationURL.path) else {
            return
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }
}

enum LaunchPlanError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "\(name) is missing."
        }
    }
}
