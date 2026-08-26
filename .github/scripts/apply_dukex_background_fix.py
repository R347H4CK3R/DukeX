#!/usr/bin/env python3
import sys
from pathlib import Path

root = Path.cwd()
xemu_path = root / "ui" / "xemu.c"
swift_path = root / "ios" / "DukeX" / "DukeX" / "Runtime" / "Core" / "EmulatorCoreRuntime.swift"
fatx_path = root / "ios" / "DukeX" / "DukeX" / "Services" / "CloudSaves" / "FATXHDDCloudSaveStore.swift"
jit_path = root / "tcg" / "ios-jit.c"

def fail(msg):
    print("ERROR:", msg, file=sys.stderr)
    raise SystemExit(1)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        fail(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

if not xemu_path.is_file() or not swift_path.is_file() or not fatx_path.is_file() or not jit_path.is_file():
    fail("DukeX source files not found")

xemu = xemu_path.read_text(encoding="utf-8")
swift = swift_path.read_text(encoding="utf-8")
fatx = fatx_path.read_text(encoding="utf-8")
jit = jit_path.read_text(encoding="utf-8")

if "void xemu_ios_set_application_active(int active)" not in xemu:
    xemu = replace_once(xemu, 'void xemu_ios_request_shutdown(void);\nvoid xemu_ios_destroy_metal_view(void);', 'void xemu_ios_request_shutdown(void);\nvoid xemu_ios_set_application_active(int active);\nvoid xemu_ios_destroy_metal_view(void);', "xemu declaration")
    xemu = replace_once(xemu, 'static XemuIOSGameplayTouchCallback ios_gameplay_touch_callback;\nstatic XemuIOSGameplayTouchEventCallback ios_gameplay_touch_event_callback;', 'static XemuIOSGameplayTouchCallback ios_gameplay_touch_callback;\nstatic XemuIOSGameplayTouchEventCallback ios_gameplay_touch_event_callback;\nstatic bool ios_lifecycle_paused_vm;', "xemu lifecycle state")
    old = '__attribute__((visibility("default")))\nvoid xemu_ios_request_shutdown(void)\n{\n    IOS_LOG("shutdown requested by native overlay");\n    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);\n}\n\nvoid *xemu_ios_get_metal_layer(void)'
    new = '__attribute__((visibility("default")))\nvoid xemu_ios_request_shutdown(void)\n{\n    IOS_LOG("shutdown requested by native overlay");\n    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);\n}\n\n__attribute__((visibility("default")))\nvoid xemu_ios_set_application_active(int active)\n{\n    /* This callback is invoked from UIKit/main-thread lifecycle observers.\n     * vm_stop() assumes the caller already owns the BQL, which is not true\n     * here and triggers bql_update_status on iOS. Use the request APIs so\n     * the emulator thread performs the transition in the proper context. */\n    if (!active) {\n        if (!ios_lifecycle_paused_vm && runstate_is_running()) {\n            IOS_LOG("application resigning active; requesting VM pause before GPU background restriction");\n            qemu_system_suspend_request();\n            ios_lifecycle_paused_vm = true;\n        }\n        return;\n    }\n\n    if (ios_lifecycle_paused_vm) {\n        IOS_LOG("application active; requesting VM wakeup after lifecycle pause");\n        ios_lifecycle_paused_vm = false;\n        qemu_system_wakeup_request(QEMU_WAKEUP_REASON_OTHER, NULL);\n    }\n}\n\nvoid *xemu_ios_get_metal_layer(void)'
    xemu = replace_once(xemu, old, new, "xemu lifecycle function")

if "loadSetApplicationActive" not in swift:
    swift = replace_once(swift, '    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias QemuSystemResetRequest = @convention(c) (Int32) -> Void', '    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias XemuSetApplicationActive = @convention(c) (Int32) -> Void\n    private typealias QemuSystemResetRequest = @convention(c) (Int32) -> Void', "swift typealias")
    swift = replace_once(swift, '    private var requestShutdown: XemuRequestShutdown?\n    private var requestSystemReset: QemuSystemResetRequest?', '    private var requestShutdown: XemuRequestShutdown?\n    private var setApplicationActive: XemuSetApplicationActive?\n    private var requestSystemReset: QemuSystemResetRequest?', "swift property")
    swift = replace_once(swift, '            let requestShutdown = loadRequestShutdown()\n            let requestSystemReset = loadRequestSystemReset()', '            let requestShutdown = loadRequestShutdown()\n            let setApplicationActive = loadSetApplicationActive()\n            let requestSystemReset = loadRequestSystemReset()', "swift loader call")
    old_task = '            Task { @MainActor in\n                await XboxPeripheralPermissionPrimer.shared.prepareIfNeeded('
    new_task = '            Task { @MainActor in\n                let notificationCenter = NotificationCenter.default\n                let resignObserver = notificationCenter.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in setApplicationActive?(0) }\n                let backgroundObserver = notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in setApplicationActive?(0) }\n                let activeObserver = notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in setApplicationActive?(1) }\n                setApplicationActive?(UIApplication.shared.applicationState == .active ? 1 : 0)\n                defer {\n                    notificationCenter.removeObserver(resignObserver)\n                    notificationCenter.removeObserver(backgroundObserver)\n                    notificationCenter.removeObserver(activeObserver)\n                }\n                await XboxPeripheralPermissionPrimer.shared.prepareIfNeeded('
    swift = replace_once(swift, old_task, new_task, "swift lifecycle observers")
    old_loader = '        self.requestShutdown = requestShutdown\n        return requestShutdown\n    }\n\n    private func loadRequestSystemReset() -> QemuSystemResetRequest? {'
    new_loader = '        self.requestShutdown = requestShutdown\n        return requestShutdown\n    }\n\n    private func loadSetApplicationActive() -> XemuSetApplicationActive? {\n        if let setApplicationActive { return setApplicationActive }\n        guard let handle else { return nil }\n        guard let symbol = dlsym(handle, "xemu_ios_set_application_active") else {\n            NSLog("xemu_ios_set_application_active is not available; background GPU protection disabled")\n            return nil\n        }\n        NSLog("Resolved xemu_ios_set_application_active")\n        let setter = unsafeBitCast(symbol, to: XemuSetApplicationActive.self)\n        setApplicationActive = setter\n        return setter\n    }\n\n    private func loadRequestSystemReset() -> QemuSystemResetRequest? {'
    swift = replace_once(swift, old_loader, new_loader, "swift symbol loader")

old_fat_timestamp = '''        let year = max(1980, components.year ?? 1980)
        let date = UInt16(((year - 1980) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        let time = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        return (date, time)'''
new_fat_timestamp = '''        let year = max(1980, components.year ?? 1980)
        let yearBits = UInt16(year - 1980)
        let monthBits = UInt16(components.month ?? 1)
        let dayBits = UInt16(components.day ?? 1)
        let hourBits = UInt16(components.hour ?? 0)
        let minuteBits = UInt16(components.minute ?? 0)
        let secondBits = UInt16((components.second ?? 0) / 2)
        let date = (yearBits << 9) | (monthBits << 5) | dayBits
        let time = (hourBits << 11) | (minuteBits << 5) | secondBits
        return (date, time)'''
if old_fat_timestamp in fatx:
    fatx = replace_once(fatx, old_fat_timestamp, new_fat_timestamp, "FATX timestamp type-check fix")
elif new_fat_timestamp not in fatx:
    fail("FATX timestamp block not found; refusing to continue with an unpatched compiler issue")

if "xemu_ios_universal_jit_debugger_attached" not in jit:
    jit = replace_once(jit, '#include <TargetConditionals.h>\n#include <libkern/OSCacheControl.h>', '#include <TargetConditionals.h>\n#include <libkern/OSCacheControl.h>\n#include <sys/sysctl.h>', "Universal.js debugger sysctl include")
    helper_anchor = '''#if XEMU_IOS_UNIVERSAL_JIT_BRK
__attribute__((noinline, optnone, naked, used))
static void *jit26_prepare_region(void *addr, size_t len)
'''
    helper_replacement = '''#if XEMU_IOS_UNIVERSAL_JIT_BRK
static bool xemu_ios_universal_jit_debugger_attached(void)
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &info_size, NULL, 0) != 0) return false;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

__attribute__((noinline, optnone, naked, used))
static void *jit26_prepare_region(void *addr, size_t len)
'''
    jit = replace_once(jit, helper_anchor, helper_replacement, "Universal.js debugger helper")
    prepare_anchor = '''    fprintf(stderr, "xemu-ios: Universal.js preparing JIT region %p (%zu bytes)\\n",
            addr, size);
    prepared_addr = jit26_prepare_region(addr, size);
'''
    prepare_replacement = '''    if (!xemu_ios_universal_jit_debugger_attached()) {
        warn_report("Universal.js broker not attached; refusing to issue BRK for JIT region %p (size %zu)", addr, size);
        return NULL;
    }
    fprintf(stderr, "xemu-ios: Universal.js debugger broker attached; preparing JIT region %p (%zu bytes)\\n", addr, size);
    prepared_addr = jit26_prepare_region(addr, size);
'''
    jit = replace_once(jit, prepare_anchor, prepare_replacement, "Universal.js pre-BRK guard")

xemu_path.write_text(xemu, encoding="utf-8")
swift_path.write_text(swift, encoding="utf-8")
fatx_path.write_text(fatx, encoding="utf-8")
jit_path.write_text(jit, encoding="utf-8")
print("Self-patch applied or already present.")
