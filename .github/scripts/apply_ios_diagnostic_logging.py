#!/usr/bin/env python3
from pathlib import Path

runtime_path = Path("ios/DukeX/DukeX/Runtime/Core/EmulatorCoreRuntime.swift")
runtime = runtime_path.read_text(encoding="utf-8")

# Enable the native core input diagnostic bridge. It already exists, but the
# launch path intentionally disabled it by assigning nil.
old = "            let setInputDiagnosticCallback: XemuSetInputDiagnosticCallback? = nil\n"
new = "            let setInputDiagnosticCallback = loadSetInputDiagnosticCallback()\n"
if old in runtime:
    runtime = runtime.replace(old, new, 1)
elif new not in runtime:
    raise SystemExit("Expected input diagnostic callback launch assignment not found")

# Make the persistent latest.log self-describing enough to correlate a device
# crash with a particular process/build environment.
needle = '''            Date: \\(ISO8601DateFormatter().string(from: Date()))
            Target: \\(plan.gameName)
'''
replacement = '''            Date: \\(ISO8601DateFormatter().string(from: Date()))
            Diagnostic Mode: enabled
            Process ID: \\(ProcessInfo.processInfo.processIdentifier)
            OS: \\(ProcessInfo.processInfo.operatingSystemVersionString)
            Device: \\(UIDevice.current.model) / \\(UIDevice.current.systemName) \\(UIDevice.current.systemVersion)
            Physical Memory: \\(ProcessInfo.processInfo.physicalMemory) bytes
            Processor Count: \\(ProcessInfo.processInfo.processorCount)
            Active Processor Count: \\(ProcessInfo.processInfo.activeProcessorCount)
            Low Power Mode: \\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "enabled" : "disabled")
            Target: \\(plan.gameName)
'''
if needle in runtime:
    runtime = runtime.replace(needle, replacement, 1)
elif "Diagnostic Mode: enabled" not in runtime:
    raise SystemExit("Expected DukeX run-log header not found")

# Log the exact dynamic loader state around loading the core. This catches
# missing frameworks/symbols before qemu_init begins.
old_loader = '''        NSLog("Loading Xemu core dylib from %@", coreURL.path)
        let openFlags = RTLD_NOW | RTLD_LOCAL
'''
new_loader = '''        NSLog("Loading Xemu core dylib from %@", coreURL.path)
        NSLog("DukeX diagnostic: pid=%d mainThread=%d os=%@", ProcessInfo.processInfo.processIdentifier, Thread.isMainThread ? 1 : 0, ProcessInfo.processInfo.operatingSystemVersionString)
        let openFlags = RTLD_NOW | RTLD_LOCAL
'''
if old_loader in runtime:
    runtime = runtime.replace(old_loader, new_loader, 1)
elif "DukeX diagnostic: pid=" not in runtime:
    raise SystemExit("Expected dynamic-loader log point not found")

runtime_path.write_text(runtime, encoding="utf-8")

# Add high-value coroutine diagnostics without changing coroutine semantics.
coroutine_path = Path("util/qemu-coroutine.c")
coroutine = coroutine_path.read_text(encoding="utf-8")
create_needle = "Coroutine *qemu_coroutine_create(CoroutineEntry *entry, void *opaque)"
if create_needle not in coroutine:
    raise SystemExit("qemu_coroutine_create not found")

# Add a marker immediately at function entry if not already present. Keep it
# CONFIG_IOS-only so non-iOS builds are untouched.
brace_needle = create_needle + "\n{\n"
entry_log = create_needle + '''
{
#ifdef CONFIG_IOS
    fprintf(stderr, "xemu_ios: coroutine create: entry=%p opaque=%p thread=%p\\n",
            (void *)entry, opaque, (void *)pthread_self());
    fflush(stderr);
#endif
'''
if "xemu_ios: coroutine create: entry=" not in coroutine:
    if brace_needle not in coroutine:
        raise SystemExit("Unexpected qemu_coroutine_create layout")
    coroutine = coroutine.replace(brace_needle, entry_log, 1)

coroutine_path.write_text(coroutine, encoding="utf-8")

# Compile the embedded core with useful symbols and frame pointers. This does
# not switch to a different coroutine backend or alter the runtime fixes.
build_path = Path("ios/scripts/build-core-ios.sh")
build = build_path.read_text(encoding="utf-8")
flag_needle = '''  "-DXBOX"
)'''
flag_replacement = '''  "-DXBOX"
  "-g3"
  "-fno-omit-frame-pointer"
  "-fno-optimize-sibling-calls"
)'''
if flag_needle in build:
    build = build.replace(flag_needle, flag_replacement, 1)
elif '"-fno-omit-frame-pointer"' not in build:
    raise SystemExit("Expected COMMON_FLAGS block not found")

build_path.write_text(build, encoding="utf-8")

# Verify all expected diagnostics landed.
patched_runtime = runtime_path.read_text(encoding="utf-8")
patched_coroutine = coroutine_path.read_text(encoding="utf-8")
patched_build = build_path.read_text(encoding="utf-8")
required_runtime = [
    "Diagnostic Mode: enabled",
    "loadSetInputDiagnosticCallback()",
    "Physical Memory:",
    "DukeX diagnostic: pid=",
]
for marker in required_runtime:
    if marker not in patched_runtime:
        raise SystemExit(f"missing runtime diagnostic marker: {marker}")
if "xemu_ios: coroutine create: entry=" not in patched_coroutine:
    raise SystemExit("coroutine creation diagnostic marker missing")
if '"-g3"' not in patched_build or '"-fno-omit-frame-pointer"' not in patched_build:
    raise SystemExit("diagnostic core compiler flags missing")

print("Enabled DukeX iOS diagnostic logging, input tracing, and symbol-friendly core build")
