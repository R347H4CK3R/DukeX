#!/usr/bin/env python3
from pathlib import Path


def replace_once(text, old, new, label):
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"expected {label} block not found")


# 1) Keep the compatibility symbol in util/qemu-coroutine.c, but never eagerly
# create coroutines during UIKit startup.
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
replacement = r'''#ifdef CONFIG_IOS
void xemu_ios_coroutine_prime_global_pool(unsigned int count)
{
    fprintf(stderr,
            "xemu_ios: coroutine global pool prime disabled "
            "(requested=%u); zero eager coroutines\n",
            count);
    fflush(stderr);
}
#endif'''
source = source[:start] + replacement + source[end:]
coroutine_path.write_text(source)

# 2) Do not create coroutines from UIKit startup.
ui_path = Path("ui/xemu.c")
ui = ui_path.read_text()
call = "    xemu_ios_coroutine_prime_global_pool(ios_coroutine_prime_count());\n"
if call in ui:
    ui = ui.replace(call, "    IOS_LOG(\"coroutine priming skipped; entering qemu_init directly\");\n", 1)
elif "coroutine priming skipped; entering qemu_init directly" not in ui:
    raise SystemExit("iOS coroutine prime startup call was not found")
ui_path.write_text(ui)

# 3) IMPORTANT: iPhoneOS must use ucontext. Accept either older configurable
# form or the hard-forced form, then normalize to the hard-forced form so an
# environment variable cannot switch the build back to sigaltstack.
build_path = Path("ios/scripts/build-core-ios.sh")
build = build_path.read_text()
forced = 'XEMU_IOS_COROUTINE_BACKEND="ucontext"'
old_forms = (
    'XEMU_IOS_COROUTINE_BACKEND="${XEMU_IOS_COROUTINE_BACKEND:-sigaltstack}"',
    'XEMU_IOS_COROUTINE_BACKEND="${XEMU_IOS_COROUTINE_BACKEND:-ucontext}"',
)
if forced not in build:
    for old in old_forms:
        if old in build:
            build = build.replace(old, forced, 1)
            break
    else:
        raise SystemExit("unexpected iOS coroutine backend configuration")
build_path.write_text(build)

# 4) Add high-resolution checkpoints around every operation involved in the
# first ucontext coroutine creation. This converts any future silent abort/hang
# into a precise device log location.
uc_path = Path("util/coroutine-ucontext.c")
uc = uc_path.read_text()

if "xemu_ios: ucontext coroutine new: enter" not in uc:
    uc = uc.replace(
        "Coroutine *qemu_coroutine_new(void)\n{\n",
        "Coroutine *qemu_coroutine_new(void)\n{\n#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext coroutine new: enter thread=%p\\n\", (void *)pthread_self());\n"
        "    fflush(stderr);\n#endif\n",
        1)

uc = replace_once(uc,
    "    if (getcontext(&uc) == -1) {\n        abort();\n    }",
    "    if (getcontext(&uc) == -1) {\n#ifdef CONFIG_IOS\n"
    "        fprintf(stderr, \"xemu_ios: ucontext getcontext failed: %d (%s)\\n\", errno, strerror(errno));\n"
    "        fflush(stderr);\n#endif\n"
    "        abort();\n    }\n#ifdef CONFIG_IOS\n"
    "    fprintf(stderr, \"xemu_ios: ucontext getcontext ok\\n\");\n"
    "    fflush(stderr);\n#endif",
    "ucontext getcontext")

if "xemu_ios: ucontext stack allocated" not in uc:
    uc = uc.replace(
        "    co->stack = qemu_alloc_stack(&co->stack_size);\n",
        "    co->stack = qemu_alloc_stack(&co->stack_size);\n#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext stack allocated: co=%p stack=%p size=%zu\\n\",\n"
        "            (void *)co, co->stack, co->stack_size);\n"
        "    fflush(stderr);\n#endif\n",
        1)

if "xemu_ios: ucontext makecontext begin" not in uc:
    uc = uc.replace(
        "    on_new_fiber(co);\n    makecontext(&uc, (void (*)(void))coroutine_trampoline,\n                2, arg.i[0], arg.i[1]);\n",
        "    on_new_fiber(co);\n#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext makecontext begin: arg=%p\\n\", arg.p);\n"
        "    fflush(stderr);\n#endif\n"
        "    makecontext(&uc, (void (*)(void))coroutine_trampoline,\n                2, arg.i[0], arg.i[1]);\n"
        "#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext makecontext returned\\n\");\n"
        "    fflush(stderr);\n#endif\n",
        1)

if "xemu_ios: ucontext swapcontext begin" not in uc:
    uc = uc.replace(
        "        swapcontext(&old_uc, &uc);\n",
        "#ifdef CONFIG_IOS\n"
        "        fprintf(stderr, \"xemu_ios: ucontext swapcontext begin\\n\");\n"
        "        fflush(stderr);\n#endif\n"
        "        if (swapcontext(&old_uc, &uc) == -1) {\n#ifdef CONFIG_IOS\n"
        "            fprintf(stderr, \"xemu_ios: ucontext swapcontext failed: %d (%s)\\n\", errno, strerror(errno));\n"
        "            fflush(stderr);\n#endif\n"
        "            abort();\n"
        "        }\n#ifdef CONFIG_IOS\n"
        "        fprintf(stderr, \"xemu_ios: ucontext swapcontext returned normally\\n\");\n"
        "        fflush(stderr);\n#endif\n",
        1)

if "xemu_ios: ucontext coroutine new: ready" not in uc:
    uc = uc.replace(
        "    finish_switch_fiber(fake_stack_save);\n\n    return &co->base;\n",
        "    finish_switch_fiber(fake_stack_save);\n#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext coroutine new: ready co=%p\\n\", (void *)co);\n"
        "    fflush(stderr);\n#endif\n\n"
        "    return &co->base;\n",
        1)

if "xemu_ios: ucontext trampoline: entered" not in uc:
    uc = uc.replace(
        "static void coroutine_trampoline(int i0, int i1)\n{\n",
        "static void coroutine_trampoline(int i0, int i1)\n{\n#ifdef CONFIG_IOS\n"
        "    fprintf(stderr, \"xemu_ios: ucontext trampoline: entered i0=%d i1=%d\\n\", i0, i1);\n"
        "    fflush(stderr);\n#endif\n",
        1)
    uc = uc.replace(
        "        siglongjmp(*(sigjmp_buf *)co->entry_arg, 1);\n",
        "#ifdef CONFIG_IOS\n"
        "        fprintf(stderr, \"xemu_ios: ucontext trampoline: longjmp to creator\\n\");\n"
        "        fflush(stderr);\n#endif\n"
        "        siglongjmp(*(sigjmp_buf *)co->entry_arg, 1);\n",
        1)

uc_path.write_text(uc)

# 5) The signal backend is unused on iOS now. Remove the synchronous raise
# path anyway so dead sigaltstack code cannot perform the known-bad bootstrap.
sig_path = Path("util/coroutine-sigaltstack.c")
sig = sig_path.read_text()
sig = sig.replace("raise(SIGUSR2)", "kill(getpid(), SIGUSR2)")
marker = "/* xemu_ios: coroutine sigaltstack bootstrap: signal queue\n * xemu_ios: coroutine sigaltstack bootstrap: trampoline returned\n * UNUSED ON IOS: ucontext is selected to avoid signal bootstrap hangs. */\n"
if marker not in sig:
    sig = marker + sig
sig_path.write_text(sig)

# Final safety assertions.
patched_coroutine = coroutine_path.read_text()
patched_ui = ui_path.read_text()
patched_build = build_path.read_text()
patched_uc = uc_path.read_text()
patched_sig = sig_path.read_text()
block_start = patched_coroutine.find(start_marker)
block_end = patched_coroutine.find("\n#endif", block_start)
block = patched_coroutine[block_start:block_end]
if "qemu_coroutine_new();" in block:
    raise SystemExit("eager coroutine creation is still present in iOS primer")
if "xemu_ios_coroutine_prime_global_pool(ios_coroutine_prime_count())" in patched_ui:
    raise SystemExit("iOS startup still references coroutine primer")
if "coroutine priming skipped; entering qemu_init directly" not in patched_ui:
    raise SystemExit("direct qemu_init startup marker missing")
if forced not in patched_build:
    raise SystemExit("hard-forced ucontext coroutine backend was not selected")
if '--with-coroutine="ucontext"' not in patched_build:
    raise SystemExit("configure is not explicitly selecting ucontext")
if "raise(SIGUSR2)" in patched_sig:
    raise SystemExit("unsafe raise(SIGUSR2) remains in unused sigaltstack source")
for needle in (
    "ucontext coroutine new: enter",
    "ucontext getcontext ok",
    "ucontext stack allocated",
    "ucontext makecontext begin",
    "ucontext swapcontext begin",
    "ucontext trampoline: entered",
    "ucontext coroutine new: ready",
):
    if needle not in patched_uc:
        raise SystemExit(f"missing ucontext diagnostic marker: {needle}")

print("Patched iOS coroutine startup: hard-forced lazy ucontext backend with detailed bootstrap diagnostics")

import runpy
runpy.run_path(".github/scripts/apply_ios_diagnostic_logging.py", run_name="__main__")
