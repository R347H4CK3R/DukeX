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
if call not in ui:
    raise SystemExit("iOS coroutine prime startup call was not found")
ui = ui.replace(call, "    IOS_LOG(\"coroutine priming skipped; entering qemu_init directly\");\n", 1)
ui_path.write_text(ui)

patched_coroutine = coroutine_path.read_text()
patched_ui = ui_path.read_text()
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

print("Patched iOS startup: coroutine priming call bypassed; compatibility helper retained")
