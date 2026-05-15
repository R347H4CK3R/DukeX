import Darwin
import Foundation
import GameController
import SwiftUI

@main
struct XemuIOSApp: App {
    @StateObject private var store = EmulatorFileStore()

    init() {
        MetalDiagnostics.configurePerformanceHUD()
        _ = GameControllerBootstrap.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.prepareAndRefresh()
                }
        }
    }
}

enum MetalDiagnostics {
    static var performanceHUDRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XEMU_IOS_METAL_HUD"] == "1" ||
            UserDefaults.standard.bool(forKey: "DukeXMetalHUDEnabled")
    }

    static func configurePerformanceHUD() {
        guard performanceHUDRequested else {
            unsetenv("MTL_HUD_ENABLED")
            unsetenv("MTL_HUD_LOG_ENABLED")
            unsetenv("MTL_HUD_LOGGING_ENABLED")
            unsetenv("MTL_HUD_LOG_SHADER_ENABLED")
            unsetenv("MTL_HUD_ENCODER_TIMING_ENABLED")
            unsetenv("MTL_HUD_SHOW_ZERO_METRICS")
            unsetenv("MTL_HUD_OPACITY")
            UserDefaults.standard.set(false, forKey: "MetalHudEnabled")
            UserDefaults.standard.set(false, forKey: "MetalHUDForceEnabled")
            UserDefaults.standard.set(false, forKey: "MetalForceHudEnabled")
            UserDefaults.standard.synchronize()
            NSLog("Metal HUD disabled")
            return
        }

        setenv("MTL_HUD_ENABLED", "1", 1)
        setenv("MTL_HUD_LOG_ENABLED", "1", 1)
        setenv("MTL_HUD_LOGGING_ENABLED", "1", 1)
        setenv("MTL_HUD_LOG_SHADER_ENABLED", "1", 1)
        setenv("MTL_HUD_ENCODER_TIMING_ENABLED", "1", 1)
        setenv("MTL_HUD_SHOW_ZERO_METRICS", "1", 1)
        setenv("MTL_HUD_OPACITY", "1.0", 1)
        let enableMoltenVKDiagnostics =
            ProcessInfo.processInfo.environment["XEMU_IOS_MVK_DIAGNOSTICS"] == "1"
        setenv("MVK_CONFIG_PERFORMANCE_TRACKING", enableMoltenVKDiagnostics ? "1" : "0", 1)
        setenv("MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT", "120", 1)
        setenv("MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE", "0", 1)
        setenv("MVK_CONFIG_LOG_LEVEL", enableMoltenVKDiagnostics ? "3" : "2", 1)
        UserDefaults.standard.set(true, forKey: "MetalHudEnabled")
        UserDefaults.standard.set(true, forKey: "MetalHUDForceEnabled")
        UserDefaults.standard.set(true, forKey: "MetalForceHudEnabled")
        UserDefaults.standard.synchronize()
        NSLog("Metal HUD requested; MoltenVK diagnostics %@", enableMoltenVKDiagnostics ? "enabled" : "disabled")
    }
}

final class GameControllerBootstrap {
    static let shared = GameControllerBootstrap()

    private var observers: [NSObjectProtocol] = []

    private init() {
        if #available(iOS 14.5, *) {
            GCController.shouldMonitorBackgroundEvents = true
        }

        logSnapshot(reason: "startup")

        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.logControllerNotification("connected", notification: notification)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.logControllerNotification("disconnected", notification: notification)
        })

        GCController.startWirelessControllerDiscovery { [weak self] in
            self?.logSnapshot(reason: "wireless discovery completed")
        }

        for delay in [0.25, 1.0, 3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.logSnapshot(reason: String(format: "delayed %.2fs", delay))
            }
        }
    }

    func logSnapshot(reason: String) {
        let controllers = GCController.controllers()
        log("snapshot \(reason): \(controllers.count) controller(s)")
        for (index, controller) in controllers.enumerated() {
            log("controller[\(index)]: \(describe(controller))")
        }
    }

    private func logControllerNotification(
        _ action: String,
        notification: Notification
    ) {
        if let controller = notification.object as? GCController {
            log("\(action): \(describe(controller))")
        } else {
            log("\(action): notification without GCController object")
        }
        logSnapshot(reason: "after \(action)")
    }

    private func describe(_ controller: GCController) -> String {
        var profiles: [String] = []
        if controller.extendedGamepad != nil {
            profiles.append("extended")
        }
        if controller.microGamepad != nil {
            profiles.append("micro")
        }
        let vendor = controller.vendorName ?? "unknown"
        let profileText = profiles.isEmpty ? "no-gamepad-profile" : profiles.joined(separator: ",")
        let attached = controller.isAttachedToDevice ? "attached" : "external"
        return "\(vendor) category=\(controller.productCategory) \(attached) profiles=\(profileText)"
    }

    private func log(_ message: String) {
        let plainLine = "xemu_ios: gamecontroller: \(message)"
        let stderrLine = "\(plainLine)\n"
        _ = stderrLine.withCString { pointer in
            fputs(pointer, stderr)
        }
        fflush(stderr)
        NSLog("%@", plainLine)
    }
}
