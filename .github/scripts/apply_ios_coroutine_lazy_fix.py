#!/usr/bin/env python3
from pathlib import Path

path = Path("util/qemu-coroutine.c")
source = path.read_text()

start_marker = "#ifdef CONFIG_IOS\nvoid xemu_ios_coroutine_prime_global_pool(unsigned int count)"
start = source.find(start_marker)
if start < 0:
    raise SystemExit("iOS coroutine pool primer was not found")

end = source.find("\n#endif", start)
if end < 0:
    raise SystemExit("end of iOS coroutine pool primer was not found")
end += len("\n#endif")

old = source[start:end]
if "qemu_coroutine_new();" not in old:
    raise SystemExit("expected eager qemu_coroutine_new() call was not found in primer")

replacement = r'''#ifdef CONFIG_IOS
void xemu_ios_coroutine_prime_global_pool(unsigned int count)
{
    /*
     * iOS must not eagerly instantiate even a single coroutine from the
     * UIKit startup path. qemu_coroutine_new() switches coroutine context and
     * aborts before guest startup on this path. Keep the compatibility entry
     * point, but intentionally make it a no-op and let QEMU create coroutines
     * lazily from its normal execution path when the pools are empty.
     */
    fprintf(stderr,
            "xemu_ios: coroutine global pool prime disabled "
            "(requested=%u); zero eager coroutines, using lazy creation\n",
            count);
    fflush(stderr);
}
#endif'''

path.write_text(source[:start] + replacement + source[end:])

patched = path.read_text()
block_start = patched.find(start_marker)
block_end = patched.find("\n#endif", block_start)
block = patched[block_start:block_end]
if "qemu_coroutine_new();" in block:
    raise SystemExit("eager coroutine creation is still present in iOS primer")
if "zero eager coroutines" not in block:
    raise SystemExit("zero-eager coroutine marker missing after patch")

print("Patched iOS coroutine primer: zero eager coroutine creation; lazy path only")
