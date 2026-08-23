#!/usr/bin/env python3
import sys
from pathlib import Path

root = Path.cwd()
xemu_path = root / "ui" / "xemu.c"
swift_path = root / "ios" / "DukeX" / "DukeX" / "Runtime" / "Core" / "EmulatorCoreRuntime.swift"

def fail(msg):
    print("ERROR:", msg, file=sys.stderr)
    raise SystemExit(1)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        fail(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

if not xemu_path.is_file() or not swift_path.is_file():
    fail("DukeX source files not found")

xemu = xemu_path.read_text(encoding="utf-8")
swift = swift_path.read_text(encoding="utf-8")

if "void xemu_ios_set_application_active(int active)" not in xemu:
    xemu = replace_once(
        xemu,
        'void xemu_ios_request_shutdown(void);\nvoid xemu_ios_destroy_metal_view(void);',
        'void xemu_ios_request_shutdown(void);\nvoid xemu_ios_set_application_active(int active);\nvoid xemu_ios_destroy_metal_view(void);',
        "xemu declaration",
    )

    xemu = replace_once(
        xemu,
        'static XemuIOSGameplayTouchCallback ios_gameplay_touch_callback;\nstatic XemuIOSGameplayTouchEventCallback ios_gameplay_touch_event_callback;',
        'static XemuIOSGameplayTouchCallback ios_gameplay_touch_callback;\nstatic XemuIOSGameplayTouchEventCallback ios_gameplay_touch_event_callback;\nstatic bool ios_lifecycle_paused_vm;',
        "xemu lifecycle state",
    )

    old = '__attribute__((visibility("default")))\nvoid xemu_ios_request_shutdown(void)\n{\n    IOS_LOG("shutdown requested by native overlay");\n    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);\n}\n\nvoid *xemu_ios_get_metal_layer(void)'
    new = '__attribute__((visibility("default")))\nvoid xemu_ios_request_shutdown(void)\n{\n    IOS_LOG("shutdown requested by native overlay");\n    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);\n}\n\n__attribute__((visibility("default")))\nvoid xemu_ios_set_application_active(int active)\n{\n    if (!active) {\n        if (!ios_lifecycle_paused_vm && runstate_is_running()) {\n            IOS_LOG("application resigning active; pausing VM before GPU background restriction");\n            vm_stop(RUN_STATE_PAUSED);\n            ios_lifecycle_paused_vm = true;\n        }\n        return;\n    }\n\n    if (ios_lifecycle_paused_vm) {\n        IOS_LOG("application active; resuming VM after lifecycle pause");\n        ios_lifecycle_paused_vm = false;\n        vm_start();\n    }\n}\n\nvoid *xemu_ios_get_metal_layer(void)'
    xemu = replace_once(xemu, old, new, "xemu lifecycle function")

if "loadSetApplicationActive" not in swift:
    swift = replace_once(
        swift,
        '    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias QemuSystemResetRequest = @convention(c) (Int32) -> Void',
        '    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias XemuSetApplicationActive = @convention(c) (Int32) -> Void\n    private typealias QemuSystemResetRequest = @convention(c) (Int32) -> Void',
        "swift typealias",
    )

    swift = replace_once(
        swift,
        '    private var requestShutdown: XemuRequestShutdown?\n    private var requestSystemReset: QemuSystemResetRequest?',
        '    private var requestShutdown: XemuRequestShutdown?\n    private var setApplicationActive: XemuSetApplicationActive?\n    private var requestSystemReset: QemuSystemResetRequest?',
        "swift property",
    )

    swift = replace_once(
        swift,
        '            let requestShutdown = loadRequestShutdown()\n            let requestSystemReset = loadRequestSystemReset()',
        '            let requestShutdown = loadRequestShutdown()\n            let setApplicationActive = loadSetApplicationActive()\n            let requestSystemReset = loadRequestSystemReset()',
        "swift loader call",
    )

    old_task = '            Task { @MainActor in\n                await XboxPeripheralPermissionPrimer.shared.prepareIfNeeded('
    new_task = '            Task { @MainActor in\n                let notificationCenter = NotificationCenter.default\n                let resignObserver = notificationCenter.addObserver(\n                    forName: UIApplication.willResignActiveNotification,\n                    object: nil,\n                    queue: .main\n                ) { _ in\n                    setApplicationActive?(0)\n                }\n                let backgroundObserver = notificationCenter.addObserver(\n                    forName: UIApplication.didEnterBackgroundNotification,\n                    object: nil,\n                    queue: .main\n                ) { _ in\n                    setApplicationActive?(0)\n                }\n                let activeObserver = notificationCenter.addObserver(\n                    forName: UIApplication.didBecomeActiveNotification,\n                    object: nil,\n                    queue: .main\n                ) { _ in\n                    setApplicationActive?(1)\n                }\n\n                setApplicationActive?(UIApplication.shared.applicationState == .active ? 1 : 0)\n\n                defer {\n                    notificationCenter.removeObserver(resignObserver)\n                    notificationCenter.removeObserver(backgroundObserver)\n                    notificationCenter.removeObserver(activeObserver)\n                }\n\n                await XboxPeripheralPermissionPrimer.shared.prepareIfNeeded('
    swift = replace_once(swift, old_task, new_task, "swift lifecycle observers")

    old_loader = '        self.requestShutdown = requestShutdown\n        return requestShutdown\n    }\n\n    private func loadRequestSystemReset() -> QemuSystemResetRequest? {'
    new_loader = '        self.requestShutdown = requestShutdown\n        return requestShutdown\n    }\n\n    private func loadSetApplicationActive() -> XemuSetApplicationActive? {\n        if let setApplicationActive { return setApplicationActive }\n        guard let handle else { return nil }\n        guard let symbol = dlsym(handle, "xemu_ios_set_application_active") else {\n            NSLog("xemu_ios_set_application_active is not available; background GPU protection disabled")\n            return nil\n        }\n        NSLog("Resolved xemu_ios_set_application_active")\n        let setter = unsafeBitCast(symbol, to: XemuSetApplicationActive.self)\n        setApplicationActive = setter\n        return setter\n    }\n\n    private func loadRequestSystemReset() -> QemuSystemResetRequest? {'
    swift = replace_once(swift, old_loader, new_loader, "swift symbol loader")

xemu_path.write_text(xemu, encoding="utf-8")
swift_path.write_text(swift, encoding="utf-8")

print("Self-patch applied or already present.")
