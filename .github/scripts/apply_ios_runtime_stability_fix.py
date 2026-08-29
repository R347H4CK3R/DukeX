#!/usr/bin/env python3
from pathlib import Path

# This script runs after apply_ios_coroutine_lazy_fix.py. That script also
# enables the broad diagnostic logger, so normalize the high-volume coroutine
# logging here and harden the XBOX/iOS GLib main-context ownership path.

# 1) Rate-limit qemu_coroutine_create diagnostics. The high call count is not
# itself a leak: QEMU deliberately recycles coroutines through its pool. Keep
# enough samples to identify entry/opaque/thread patterns without flooding the
# persistent iOS log or perturbing timing.
coroutine_path = Path("util/qemu-coroutine.c")
coroutine = coroutine_path.read_text(encoding="utf-8")
old_create_log = '''#ifdef CONFIG_IOS
    fprintf(stderr, "xemu_ios: coroutine create: entry=%p opaque=%p thread=%p\\n",
            (void *)entry, opaque, (void *)pthread_self());
    fflush(stderr);
#endif
'''
new_create_log = '''#ifdef CONFIG_IOS
    static unsigned long long ios_diag_create_count;
    unsigned long long ios_diag_id =
        __atomic_add_fetch(&ios_diag_create_count, 1, __ATOMIC_RELAXED);
    bool ios_diag_log = ios_diag_id <= 32 ||
                        (ios_diag_id & (ios_diag_id - 1)) == 0 ||
                        (ios_diag_id % 1000) == 0;

    if (ios_diag_log) {
        fprintf(stderr,
                "xemu_ios: coroutine create #%llu: entry=%p opaque=%p thread=%p\\n",
                ios_diag_id, (void *)entry, opaque, (void *)pthread_self());
        if (ios_diag_id >= 4096) {
            fprintf(stderr,
                    "xemu_ios: coroutine create volume high (%llu); "
                    "pool reuse is expected, backend allocations are logged separately\\n",
                    ios_diag_id);
        }
        fflush(stderr);
    }
#endif
'''
if old_create_log in coroutine:
    coroutine = coroutine.replace(old_create_log, new_create_log, 1)
elif "coroutine create volume high" not in coroutine:
    raise SystemExit("expected iOS coroutine creation diagnostic block not found")
coroutine_path.write_text(coroutine, encoding="utf-8")

# 2) Rate-limit backend stack-allocation logging and add total allocation IDs.
# qemu_coroutine_new() means a real heap-backed coroutine stack was allocated;
# qemu_coroutine_create() can simply reuse one from the pool.
sig_path = Path("util/coroutine-sigaltstack.c")
sig = sig_path.read_text(encoding="utf-8")
old_new_log = '''    fprintf(stderr,
            "xemu_ios: sigaltstack coroutine new: enter (arm64 direct) co=%p stack=%p size=%zu sp=%p\\n",
            (void *)co, co->stack, co->stack_size, (void *)stack_top);
    fflush(stderr);
'''
new_new_log = '''    static unsigned long long ios_backend_new_count;
    unsigned long long ios_backend_new_id =
        __atomic_add_fetch(&ios_backend_new_count, 1, __ATOMIC_RELAXED);
    bool ios_backend_new_log = ios_backend_new_id <= 32 ||
                               (ios_backend_new_id & (ios_backend_new_id - 1)) == 0 ||
                               (ios_backend_new_id % 256) == 0;
    if (ios_backend_new_log) {
        fprintf(stderr,
                "xemu_ios: arm64 coroutine backend new #%llu co=%p stack=%p size=%zu sp=%p\\n",
                ios_backend_new_id, (void *)co, co->stack, co->stack_size,
                (void *)stack_top);
        fflush(stderr);
    }
'''
if old_new_log in sig:
    sig = sig.replace(old_new_log, new_new_log, 1)
elif "arm64 coroutine backend new #" not in sig:
    raise SystemExit("expected ARM64 coroutine backend allocation log not found")
sig_path.write_text(sig, encoding="utf-8")

# 3) Fix the shutdown GLib assertion seen on iOS. g_main_context_acquire()
# returns FALSE when another thread currently owns the context. The existing
# XBOX main-loop code ignored that return value and unconditionally released
# the context, which produces:
#   g_main_context_release_unlocked: assertion 'context->owner_count > 0' failed
# On iOS, skip this poll iteration when ownership could not be acquired.
main_loop_path = Path("util/main-loop.c")
main_loop = main_loop_path.read_text(encoding="utf-8")
old_acquire = '''    g_main_context_acquire(context);

    glib_pollfds_fill(&timeout);
'''
new_acquire = '''#if defined(XBOX) && defined(CONFIG_IOS)
    if (!g_main_context_acquire(context)) {
        static unsigned int ios_context_busy_count;
        unsigned int busy =
            __atomic_add_fetch(&ios_context_busy_count, 1, __ATOMIC_RELAXED);
        if (busy <= 8 || (busy & (busy - 1)) == 0) {
            fprintf(stderr,
                    "xemu_ios: GLib main context busy; skipping poll iteration #%u\\n",
                    busy);
            fflush(stderr);
        }
        return 0;
    }
#else
    g_main_context_acquire(context);
#endif

    glib_pollfds_fill(&timeout);
'''
if old_acquire in main_loop:
    main_loop = main_loop.replace(old_acquire, new_acquire, 1)
elif "GLib main context busy; skipping poll iteration" not in main_loop:
    raise SystemExit("expected GLib main-context acquire site not found")
main_loop_path.write_text(main_loop, encoding="utf-8")

# Final assertions: fail the Actions job early if any part of this hardening
# silently stops applying after an upstream/source-layout change.
patched_coroutine = coroutine_path.read_text(encoding="utf-8")
patched_sig = sig_path.read_text(encoding="utf-8")
patched_main_loop = main_loop_path.read_text(encoding="utf-8")
for marker in (
    "coroutine create volume high",
    "ios_diag_create_count",
):
    if marker not in patched_coroutine:
        raise SystemExit(f"missing coroutine diagnostic hardening marker: {marker}")
for marker in (
    "arm64 coroutine backend new #",
    "ios_backend_new_count",
):
    if marker not in patched_sig:
        raise SystemExit(f"missing backend allocation diagnostic marker: {marker}")
for marker in (
    "if (!g_main_context_acquire(context))",
    "GLib main context busy; skipping poll iteration",
):
    if marker not in patched_main_loop:
        raise SystemExit(f"missing GLib ownership hardening marker: {marker}")

print("Applied iOS runtime stability hardening: GLib ownership + coroutine diagnostics")
