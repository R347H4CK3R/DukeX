import Darwin
import Foundation

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
