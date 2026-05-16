import Foundation
import UniformTypeIdentifiers

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

enum UniversalJITSupport {
    static var requiresUniversalJS: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    static func effectiveEnabled(for setting: Bool) -> Bool {
        setting && requiresUniversalJS
    }

    static func environmentValue(for setting: Bool) -> String {
        effectiveEnabled(for: setting) ? "1" : "0"
    }
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

enum LaunchPlanError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "\(name) is missing."
        }
    }
}
