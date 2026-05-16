import Foundation
import QuartzCore

enum MetalHUDLayerConfigurator {
    static func apply(to layer: CAMetalLayer) {
        guard MetalDiagnostics.performanceHUDRequested else {
            layer.developerHUDProperties = [
                "mode": "disabled",
                "logging": "disabled",
            ]
            return
        }

        layer.developerHUDProperties = [
            "mode": "main",
            "logging": "default",
            "positionX": 12,
            "positionY": 12,
            "MTL_HUD_ENABLED": 1,
            "MTL_HUD_LOG_ENABLED": 1,
            "MTL_HUD_LOG_SHADER_ENABLED": 1,
            "MTL_HUD_ENCODER_TIMING_ENABLED": 1,
            "MTL_HUD_SHOW_ZERO_METRICS": 1,
            "MTL_HUD_OPACITY": 1.0,
        ]
        NSLog("Metal HUD developer properties applied to CAMetalLayer")
    }
}

enum PresentPacingLayerConfigurator {
    static func apply(to layer: CAMetalLayer) {
        let mode = PresentPacingMode.current
        let forceThirtyFPSLock =
            UserDefaults.standard.object(forKey: "DukeXForceThirtyFPSLockEnabled") as? Bool ?? false
        let displaySyncEnabled = forceThirtyFPSLock ? true : mode.displaySyncEnabled
        let nominalFPS = forceThirtyFPSLock ? 30 : mode.nominalFramesPerSecondValue
        layer.setBoolWithSelector("setDisplaySyncEnabled:", value: displaySyncEnabled)
        layer.setIntWithSelector("setNominalFramesPerSecond:", value: nominalFPS)
        NSLog(
            "Native Metal presenter pacing applied: %@ force30=%@ displaySync=%@ nominalFPS=%d",
            mode.rawValue,
            forceThirtyFPSLock ? "1" : "0",
            displaySyncEnabled ? "1" : "0",
            nominalFPS
        )
    }
}

extension NSObject {
    func setBoolWithSelector(_ selectorName: String, value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = method(for: selector) else {
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(implementation, to: Setter.self)(self, selector, value)
    }

    func setIntWithSelector(_ selectorName: String, value: Int) {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = method(for: selector) else {
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(implementation, to: Setter.self)(self, selector, value)
    }
}
