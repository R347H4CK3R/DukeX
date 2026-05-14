/*
 * iOS Universal.js JIT bridge helpers.
 *
 * This is intentionally tiny: StikDebug's Universal.js script expects arm64
 * apps to request JIT-region preparation through brk #0xf00d with x16 = 1.
 */
#ifndef TCG_IOS_JIT_H
#define TCG_IOS_JIT_H

#include "qemu/osdep.h"

void xemu_ios_universal_jit_set_enabled(bool enabled);
void xemu_ios_universal_jit_set_alias_backed(bool enabled);
bool xemu_ios_universal_jit_is_enabled(void);
void *xemu_ios_universal_jit_prepare_region(void *addr, size_t size);
bool xemu_ios_universal_jit_copy_code(void *dst, const void *src, size_t size);
bool xemu_ios_universal_jit_probe_split(void *rw_addr, void *rx_addr);

#endif /* TCG_IOS_JIT_H */
