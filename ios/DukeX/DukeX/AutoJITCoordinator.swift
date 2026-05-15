import Combine
import Foundation
import UIKit

enum CoverSelectionError: LocalizedError {
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "The selected image could not be loaded."
        }
    }
}

enum AutoJITLaunchTarget: String {
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
final class StikDebugAutoJITCoordinator: ObservableObject {
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
