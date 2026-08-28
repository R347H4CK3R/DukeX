#!/usr/bin/env python3
from pathlib import Path

# 1) Keep the compatibility symbol in util/qemu-coroutine.c, but make it a no-op.
coroutine_path = Path("util/qemu-coroutine.c")
source = coroutine_path.read_text()

start_marker = "#ifdef CONFIG_IOS\nvoid xemu_ios_coroutine_prime_global_pool(unsigned int count)"
start = source.find(start_marker)
if start < 0:
    raise SystemExit("iOS coroutine pool primer was not found")

end = source.find("\n#endif", start)
if end < 0:
    raise SystemExit("end of iOS coroutine pool primer was not found")
end += len("\n#endif")

old = source[start:end]
if "qemu_coroutine_new();" not in old and "zero eager coroutines" not in old:
    raise SystemExit("unexpected iOS coroutine primer layout")

replacement = r'''#ifdef CONFIG_IOS
void xemu_ios_coroutine_prime_global_pool(unsigned int count)
{
    /* Compatibility entry point only. iOS startup must never pre-create
     * coroutines from the UIKit path. */
    fprintf(stderr,
            "xemu_ios: coroutine global pool prime disabled "
            "(requested=%u); zero eager coroutines\n",
            count);
    fflush(stderr);
}
#endif'''

coroutine_path.write_text(source[:start] + replacement + source[end:])

# 2) Remove the startup call entirely from ui/xemu.c. Keep the count helper in
# place because ios/scripts/build-core-ios.sh still patches its defaults to zero
# as a compatibility check. Since nothing calls the helper, no priming occurs.
ui_path = Path("ui/xemu.c")
ui = ui_path.read_text()
call = "    xemu_ios_coroutine_prime_global_pool(ios_coroutine_prime_count());\n"
if call in ui:
    ui = ui.replace(call, "    IOS_LOG(\"coroutine priming skipped; entering qemu_init directly\");\n", 1)
elif "coroutine priming skipped; entering qemu_init directly" not in ui:
    raise SystemExit("iOS coroutine prime startup call was not found")
ui_path.write_text(ui)

# 3) iPhoneOS exposes ucontext symbols, but getcontext() is not usable in this
# embedded runtime. Use QEMU's sigaltstack backend for normal lazy creation.
build_path = Path("ios/scripts/build-core-ios.sh")
build = build_path.read_text()
old_backend = 'XEMU_IOS_COROUTINE_BACKEND="${XEMU_IOS_COROUTINE_BACKEND:-ucontext}"'
new_backend = 'XEMU_IOS_COROUTINE_BACKEND="${XEMU_IOS_COROUTINE_BACKEND:-sigaltstack}"'
if old_backend in build:
    build = build.replace(old_backend, new_backend, 1)
elif new_backend not in build:
    raise SystemExit("unexpected iOS coroutine backend configuration")
build_path.write_text(build)

# 4) Fix the iOS sigaltstack bootstrap itself. The previous iOS-only raise()
# path can return without the SA_ONSTACK trampoline having run under an
# embedded LiveContainer/StikDebug process. That reaches the explicit abort in
# qemu_coroutine_new(). Keep SIGUSR2 blocked while queueing it to this pthread,
# then atomically wait with sigsuspend(), matching QEMU's proven POSIX path.
# Add stage logging so any remaining platform failure is identifiable directly
# from the device log rather than only as qemu_coroutine_new()+offset.
sig_path = Path("util/coroutine-sigaltstack.c")
sig = sig_path.read_text()
old_ios = r'''#ifdef CONFIG_IOS
    /*
     * On iOS the long-lived emulator runs on a DispatchQueue-backed pthread.
     * LiveContainer/StikDebug can leave SIGUSR2 pending while sigsuspend()
     * waits, which deadlocks the very first coroutine bootstrap.  Deliver the
     * signal synchronously on this thread instead: raise() does not return
     * until our handler has run, and SA_ONSTACK still switches to the freshly
     * installed coroutine stack.  Restore the original mask below exactly as
     * the generic path does.
     */
    pthread_sigmask(SIG_UNBLOCK, &sigs, NULL);
    if (raise(SIGUSR2) != 0 || !coTS->tr_called) {
        abort();
    }
#else
    pthread_kill(pthread_self(), SIGUSR2);
    sigfillset(&sigs);
    sigdelset(&sigs, SIGUSR2);
    while (!coTS->tr_called) {
        sigsuspend(&sigs);
    }
#endif'''
new_ios = r'''#ifdef CONFIG_IOS
    fprintf(stderr, "xemu_ios: coroutine sigaltstack bootstrap: signal queue\n");
    fflush(stderr);
    {
        int kill_ret = pthread_kill(pthread_self(), SIGUSR2);
        if (kill_ret != 0) {
            fprintf(stderr,
                    "xemu_ios: coroutine sigaltstack pthread_kill failed: %d (%s)\n",
                    kill_ret, strerror(kill_ret));
            fflush(stderr);
            abort();
        }
    }
    sigfillset(&sigs);
    sigdelset(&sigs, SIGUSR2);
    while (!coTS->tr_called) {
        int suspend_ret = sigsuspend(&sigs);
        if (suspend_ret < 0 && errno != EINTR) {
            fprintf(stderr,
                    "xemu_ios: coroutine sigaltstack sigsuspend failed: %d (%s)\n",
                    errno, strerror(errno));
            fflush(stderr);
            abort();
        }
    }
    fprintf(stderr, "xemu_ios: coroutine sigaltstack bootstrap: trampoline returned\n");
    fflush(stderr);
#else
    pthread_kill(pthread_self(), SIGUSR2);
    sigfillset(&sigs);
    sigdelset(&sigs, SIGUSR2);
    while (!coTS->tr_called) {
        sigsuspend(&sigs);
    }
#endif'''
if old_ios in sig:
    sig = sig.replace(old_ios, new_ios, 1)
elif "coroutine sigaltstack bootstrap: signal queue" not in sig:
    raise SystemExit("expected iOS sigaltstack bootstrap block not found")

# Give the other explicit failure sites useful iOS diagnostics.
sig = sig.replace(
    '''    if (sigaction(SIGUSR2, &sa, &osa) != 0) {\n        abort();\n    }''',
    '''    if (sigaction(SIGUSR2, &sa, &osa) != 0) {\n#ifdef CONFIG_IOS\n        fprintf(stderr, "xemu_ios: coroutine sigaction failed: %d (%s)\\n", errno, strerror(errno));\n        fflush(stderr);\n#endif\n        abort();\n    }''',
    1,
)
sig = sig.replace(
    '''    if (sigaltstack(&ss, &oss) < 0) {\n        abort();\n    }''',
    '''    if (sigaltstack(&ss, &oss) < 0) {\n#ifdef CONFIG_IOS\n        fprintf(stderr, "xemu_ios: coroutine sigaltstack install failed: %d (%s)\\n", errno, strerror(errno));\n        fflush(stderr);\n#endif\n        abort();\n    }''',
    1,
)
sig = sig.replace(
    '''    if (sigaltstack(&ss, NULL) < 0) {\n        abort();\n    }''',
    '''    if (sigaltstack(&ss, NULL) < 0) {\n#ifdef CONFIG_IOS\n        fprintf(stderr, "xemu_ios: coroutine sigaltstack disable failed: %d (%s)\\n", errno, strerror(errno));\n        fflush(stderr);\n#endif\n        abort();\n    }''',
    1,
)
sig_path.write_text(sig)

patched_coroutine = coroutine_path.read_text()
patched_ui = ui_path.read_text()
patched_build = build_path.read_text()
patched_sig = sig_path.read_text()
block_start = patched_coroutine.find(start_marker)
block_end = patched_coroutine.find("\n#endif", block_start)
block = patched_coroutine[block_start:block_end]
if "qemu_coroutine_new();" in block:
    raise SystemExit("eager coroutine creation is still present in iOS primer")
if "xemu_ios_coroutine_prime_global_pool(ios_coroutine_prime_count())" in patched_ui:
    raise SystemExit("iOS startup still references coroutine primer")
if "ios_coroutine_prime_count" not in patched_ui:
    raise SystemExit("iOS coroutine count compatibility helper is missing")
if "coroutine priming skipped; entering qemu_init directly" not in patched_ui:
    raise SystemExit("direct qemu_init startup marker missing")
if new_backend not in patched_build:
    raise SystemExit("sigaltstack coroutine backend was not selected")
if "raise(SIGUSR2)" in patched_sig:
    raise SystemExit("unsafe iOS raise() coroutine bootstrap is still present")
if "coroutine sigaltstack bootstrap: trampoline returned" not in patched_sig:
    raise SystemExit("iOS sigaltstack bootstrap fix missing")

print("Patched iOS coroutine startup: lazy sigaltstack backend with pthread-directed bootstrap")

# Apply the diagnostic-only instrumentation after the functional coroutine fix.
# Keeping this as a separate script makes it easy to remove or reduce logging
# later without touching the crash fix itself.
import runpy
runpy.run_path(".github/scripts/apply_ios_diagnostic_logging.py", run_name="__main__")
