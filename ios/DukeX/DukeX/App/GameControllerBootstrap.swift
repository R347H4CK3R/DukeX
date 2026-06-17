import Darwin
import Foundation
import GameController

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
        let batteryText: String
        if let battery = controller.battery {
            let level = Int((min(max(battery.batteryLevel, 0), 1) * 100).rounded())
            batteryText = "battery=\(level)% state=\(battery.batteryState.rawValue)"
        } else {
            batteryText = "battery=unavailable"
        }
        return "\(vendor) category=\(controller.productCategory) \(attached) profiles=\(profileText) \(batteryText)"
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
