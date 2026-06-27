#if os(macOS) || targetEnvironment(macCatalyst)
import Darwin
import Foundation

struct XemuDesktopLaunchPlan: Identifiable, Equatable {
    let id = UUID()
    let configURL: URL
    let arguments: [String]
    let jitMode: RuntimeJITMode
    let requiresJITHandoff: Bool
    let universalJITEnabled: Bool
    let gameName: String
    let titleID: String?
    let isDashboard: Bool
    let xboxCameraEnabled: Bool
    let xboxHeadsetMicEnabled: Bool
    let manicSkinPortraitURL: URL?
    let manicSkinLandscapeURL: URL?
    let shaderCacheURL: URL

    var commandLine: String {
        arguments.map(Self.shellQuoted).joined(separator: " ")
    }

    static func make(
        documentsURL: URL,
        bios: LibraryFile,
        mcpx: LibraryFile,
        eeprom: LibraryFile?,
        hdd: LibraryFile,
        game: LibraryFile?,
        gamesDirectoryURL: URL,
        universalJITEnabled: Bool,
        networkSettings: NetworkSettings,
        tbCacheSize: TBCacheSize,
        desktopAccelerationMode: DesktopAccelerationMode,
        desktopRendererBackend: DesktopRendererBackend,
        desktopGameResolutionScale: DesktopGameResolutionScale,
        desktopDisplayAspectRatio: DesktopDisplayAspectRatio,
        xemuShowMenubarEnabled: Bool,
        xemuHideCursorEnabled: Bool,
        xemuBackgroundInputCaptureEnabled: Bool,
        xemuShaderCacheEnabled: Bool,
        shaderCacheURL: URL,
        xboxCameraEnabled: Bool,
        xboxHeadsetMicEnabled: Bool,
        manicSkinPortraitURL: URL?,
        manicSkinLandscapeURL: URL?
    ) throws -> XemuDesktopLaunchPlan {
        let configURL = documentsURL.appendingPathComponent("xemu-desktop.toml")
        let gamesPath = game?.url.deletingLastPathComponent().path ?? gamesDirectoryURL.path
        let dvdPath = game?.url.path ?? ""
        let launchName = game?.displayName ?? "Xbox Dashboard"
        let titleID = GameLaunchLink.normalizedTitleID(game?.titleID)
        let eepromPathLine = eeprom.map {
            "eeprom_path = \(tomlQuoted($0.url.path))\n"
        } ?? ""

        let toml = """
        [general]
        show_welcome = false
        skip_boot_anim = false
        games_dir = \(tomlQuoted(gamesPath))

        [display]
        renderer = \(tomlQuoted(desktopRendererBackend.tomlValue))

        [display.quality]
        surface_scale = \(desktopGameResolutionScale.rawValue)

        [display.ui]
        show_menubar = \(tomlBool(xemuShowMenubarEnabled))
        show_notifications = true
        hide_cursor = \(tomlBool(xemuHideCursorEnabled))
        aspect_ratio = \(tomlQuoted(desktopDisplayAspectRatio.tomlValue))

        [perf]
        cache_shaders = \(tomlBool(xemuShaderCacheEnabled))

        [input]
        auto_bind = true
        background_input_capture = \(tomlBool(xemuBackgroundInputCaptureEnabled))

        [net]
        enable = true
        backend = "nat"

        [[net.nat.forward_ports]]
        host = \(networkSettings.effectiveHostPort)
        guest = \(networkSettings.effectiveGuestPort)
        protocol = \(tomlQuoted(networkSettings.effectivePortProtocol))

        [sys]
        mem_limit = "64"
        avpack = "hdtv"

        [sys.files]
        bootrom_path = \(tomlQuoted(mcpx.url.path))
        flashrom_path = \(tomlQuoted(bios.url.path))
        hdd_path = \(tomlQuoted(hdd.url.path))
        \(eepromPathLine)dvd_path = \(tomlQuoted(dvdPath))
        """

        try toml.write(to: configURL, atomically: true, encoding: .utf8)

        if let dnsServer = networkSettings.effectiveDNSServer {
            setenv("XEMU_NAT_DIRECT_DNS", dnsServer, 1)
        } else {
            unsetenv("XEMU_NAT_DIRECT_DNS")
        }

        let arguments = ["xemu"] +
            desktopAccelerationMode.launchArguments(tbCacheSize: tbCacheSize) +
            ["-config_path", configURL.path]

        return XemuDesktopLaunchPlan(
            configURL: configURL,
            arguments: arguments,
            jitMode: RuntimeJITMode.current,
            requiresJITHandoff: false,
            universalJITEnabled: false,
            gameName: launchName,
            titleID: titleID,
            isDashboard: game == nil,
            xboxCameraEnabled: false,
            xboxHeadsetMicEnabled: xboxHeadsetMicEnabled,
            manicSkinPortraitURL: manicSkinPortraitURL,
            manicSkinLandscapeURL: manicSkinLandscapeURL,
            shaderCacheURL: shaderCacheURL
        )
    }

    private static func tomlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func tomlBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
