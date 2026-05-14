/*
 * iOS Universal.js JIT bridge helpers.
 *
 * Copyright (C) 2026
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include "qemu/osdep.h"
#include "qemu/error-report.h"
#include "tcg/ios-jit.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <libkern/OSCacheControl.h>
#endif

static bool universal_jit_enabled;
static bool universal_jit_alias_backed;

#if defined(__APPLE__) && defined(__aarch64__) && TARGET_OS_IPHONE && \
    !TARGET_OS_SIMULATOR
#define XEMU_IOS_UNIVERSAL_JIT_BRK 1
#else
#define XEMU_IOS_UNIVERSAL_JIT_BRK 0
#endif

#if XEMU_IOS_UNIVERSAL_JIT_BRK
__attribute__((noinline, optnone, naked, used))
static void *jit26_prepare_region(void *addr, size_t len)
{
    __asm__ volatile(
        "mov x16, #1\n"
        "brk #0xf00d\n"
        "ret\n"
    );
}

__attribute__((noinline, optnone, naked, used))
static void jit26_detach(void)
{
    __asm__ volatile(
        "mov x16, #0\n"
        "brk #0xf00d\n"
        "ret\n"
    );
}

__attribute__((noinline, optnone, naked, used))
static void jit26_send_script(const char *script, size_t len)
{
    __asm__ volatile(
        "mov x16, #2\n"
        "brk #0xf00d\n"
        "ret\n"
    );
}

__attribute__((noinline, optnone, naked, used))
static uint64_t jit26_copy_code(void *dst, const void *src, size_t len)
{
    __asm__ volatile(
        "mov x16, #3\n"
        "brk #0xf00d\n"
        "ret\n"
    );
}

static void ios_jit_patch_universal_script(bool force)
{
    static bool patch_sent;
    static const char patch_script[] =
        "if(!globalThis.xemu_orig_send_command){"
        "globalThis.xemu_orig_send_command=send_command;"
        "send_command=function(cmd){"
        "if(typeof cmd==='string'&&cmd.startsWith('vCont;S')){"
        "log('xemu-ios: swallowing non-BRK signal continue '+cmd);"
        "return 'OK';"
        "}"
        "return globalThis.xemu_orig_send_command(cmd);"
        "};"
        "}"
        "commands[1]=function(brkResponse){"
        "if(x0==0n&&x1==0n){return;}"
        "let jitPageAddress=x0;"
        "if(x0==0n){"
        "let r=send_command('_M'+x1.toString(16)+',rx');"
        "log('patched requestRXResponse = '+r);"
        "if(!r||r.length===0){log('patched prepare: RX allocation failed');return;}"
        "jitPageAddress=BigInt('0x'+r);"
        "log('patched allocated JIT page at address: 0x'+jitPageAddress.toString(16));"
        "}"
        "let p=prepare_memory_region(Number(jitPageAddress),Number(x1));"
        "log('patched prepareJITPageResponse = '+p);"
        "let ret=(p==='OK')?jitPageAddress:0n;"
        "let w=send_command('P0='+numberToLittleEndianHexString(ret)+';thread:'+tid+';');"
        "log('patched putX0Response = '+w);"
        "};"
        "commands[3]=function(brkResponse){"
        "let dst=x0,src=x1,size=0n,ok=true,err='';"
        "try{"
        "let m=/02:(?<reg>[0-9a-f]{16});/.exec(brkResponse);"
        "size=m?littleEndianHexStringToNumber(m.groups.reg):0n;"
        "const C=0x1e0n;"
        "for(let i=0n;i<size;i+=C){"
        "let n=(i+C<=size)?C:(size-i);"
        "let r=send_command('m'+(src+i).toString(16)+','+n.toString(16));"
        "if(!r||r.length<Number(n*2n)){ok=false;err='short-read';break;}"
        "let h=r.slice(0,Number(n*2n));"
        "let w=send_command('M'+(dst+i).toString(16)+','+n.toString(16)+':'+h);"
        "if(w!=='OK'){ok=false;err='write-'+w;break;}"
        "}"
        "}catch(e){ok=false;err='exception-'+e;}"
        "let ret=ok?0n:1n;"
        "let p=send_command('P0='+numberToLittleEndianHexString(ret)+';thread:'+tid+';');"
        "log('patched copyCode size=0x'+size.toString(16)+' ok='+ok+' err='+err+' putX0='+p);"
        "};";

    if (patch_sent && !force) {
        return;
    }

    patch_sent = true;
    fprintf(stderr, "xemu-ios: Universal.js patch: sending Number bridge override%s\n",
            force ? " (forced)" : "");
    jit26_send_script(patch_script, sizeof(patch_script) - 1);
    fprintf(stderr, "xemu-ios: Universal.js patch: returned\n");
}

static void ios_jit_patch_universal_script_once(void)
{
    ios_jit_patch_universal_script(false);
}

static void ios_jit_repatch_universal_script(void)
{
    ios_jit_patch_universal_script(true);
}

static void ios_jit_write_probe(void *addr)
{
    uint32_t *code = (uint32_t *)((char *)addr + 4);

    /*
     * bti c; mov x0, #42; ret
     *
     * Keep byte 0 of the page free: StikDebug's iOS 26 helper writes a marker
     * byte at each 16 KB page boundary while preparing executable memory.
     */
    code[0] = 0xd503245fu;
    code[1] = 0xd2800540u;
    code[2] = 0xd65f03c0u;
    sys_icache_invalidate(code, 12);
    fprintf(stderr, "xemu-ios: Universal.js JIT probe: wrote %p\n", code);
}

static void ios_jit_call_probe(void *addr)
{
    typedef uint64_t (*probe_fn)(void);
    void *code = (char *)addr + 4;
    uint64_t result;

    fprintf(stderr, "xemu-ios: Universal.js JIT probe: calling %p\n", code);
    result = ((probe_fn)code)();
    fprintf(stderr, "xemu-ios: Universal.js JIT probe: result=%" PRIu64 "\n",
            result);
}

static void ios_jit_sync_executable(void *addr, size_t size)
{
    sys_dcache_flush(addr, size);
    sys_icache_invalidate(addr, size);
}

static void ios_jit_sync_alias(const void *rw_addr, void *rx_addr, size_t size)
{
    sys_dcache_flush((void *)rw_addr, size);
    sys_icache_invalidate(rx_addr, size);
}

static size_t ios_jit_first_mismatch(const void *dst, const void *src,
                                     size_t size)
{
    const uint8_t *d = dst;
    const uint8_t *s = src;

    for (size_t i = 0; i < size; i++) {
        if (d[i] != s[i]) {
            return i;
        }
    }
    return SIZE_MAX;
}

static bool ios_jit_try_direct_rx_copy(void *dst, const void *src, size_t size)
{
    static bool checked;
    static bool enabled;
    const char *env = getenv("XEMU_IOS_DIRECT_RWX_COPY");
    size_t page_size = getpagesize();
    uintptr_t start = (uintptr_t)dst & ~(uintptr_t)(page_size - 1);
    uintptr_t end = ROUND_UP((uintptr_t)dst + size, page_size);
    size_t len = end - start;
    int saved_errno;

    if (env == NULL || g_ascii_strcasecmp(env, "1") != 0) {
        return false;
    }

    if (enabled) {
        if (mprotect((void *)start, len,
                     PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
            memcpy(dst, src, size);
            ios_jit_sync_executable(dst, size);
            if (mprotect((void *)start, len, PROT_READ | PROT_EXEC) != 0) {
                saved_errno = errno;
                warn_report("direct RX copy disabled restoring RX for %p "
                            "(%zu bytes): %s",
                            (void *)start, len, g_strerror(saved_errno));
                enabled = false;
                return false;
            }
            return true;
        }
        saved_errno = errno;
        warn_report("direct RX copy disabled for %p (%zu bytes): %s",
                    (void *)start, len, g_strerror(saved_errno));
        enabled = false;
        return false;
    }

    if (checked) {
        return false;
    }

    checked = true;
    if (mprotect((void *)start, len, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        saved_errno = errno;
        fprintf(stderr,
                "xemu-ios: direct RWX copy unavailable for %p (%zu bytes): %s\n",
                (void *)start, len, g_strerror(saved_errno));
        return false;
    }

    memcpy(dst, src, size);
    ios_jit_sync_executable(dst, size);
    if (mprotect((void *)start, len, PROT_READ | PROT_EXEC) != 0) {
        saved_errno = errno;
        fprintf(stderr,
                "xemu-ios: direct RWX copy unavailable restoring RX for %p "
                "(%zu bytes): %s\n",
                (void *)start, len, g_strerror(saved_errno));
        return false;
    }

    enabled = true;
    fprintf(stderr,
            "xemu-ios: direct RWX/RX copy enabled via mprotect "
            "(page size %zu)\n",
            page_size);
    return true;
}
#endif

void xemu_ios_universal_jit_set_enabled(bool enabled)
{
    universal_jit_enabled = enabled;
}

void xemu_ios_universal_jit_set_alias_backed(bool enabled)
{
    universal_jit_alias_backed = enabled;
}

bool xemu_ios_universal_jit_is_enabled(void)
{
    const char *env = getenv("XEMU_IOS_UNIVERSAL_JIT");

    return universal_jit_enabled ||
           (env != NULL && g_ascii_strcasecmp(env, "0") != 0 &&
            g_ascii_strcasecmp(env, "false") != 0 &&
            g_ascii_strcasecmp(env, "no") != 0);
}

void *xemu_ios_universal_jit_prepare_region(void *addr, size_t size)
{
#if XEMU_IOS_UNIVERSAL_JIT_BRK
    void *prepared_addr;
    const char *detach_env;

    if (!xemu_ios_universal_jit_is_enabled() || size == 0) {
        return addr;
    }

    fprintf(stderr, "xemu-ios: Universal.js preparing JIT region %p (%zu bytes)\n",
            addr, size);
    prepared_addr = jit26_prepare_region(addr, size);
    if (prepared_addr == NULL) {
        warn_report("Universal.js failed to prepare JIT region %p (size %zu)",
                    addr, size);
        return NULL;
    }
    if (prepared_addr != addr) {
        warn_report("Universal.js prepared unexpected JIT address %p "
                    "(requested %p, size %zu)",
                    prepared_addr, addr, size);
    }
    detach_env = getenv("XEMU_IOS_UNIVERSAL_JIT_DETACH");
    if (detach_env == NULL || g_ascii_strcasecmp(detach_env, "0") != 0) {
        fprintf(stderr, "xemu-ios: Universal.js detach broker\n");
        jit26_detach();
    }
    return prepared_addr;
#else
    (void)size;
    return addr;
#endif
}

bool xemu_ios_universal_jit_copy_code(void *dst, const void *src, size_t size)
{
#if XEMU_IOS_UNIVERSAL_JIT_BRK
    static uint64_t copy_count;
    uint64_t copy_index;
    uint64_t ret;
    int attempt;

    if (!xemu_ios_universal_jit_is_enabled() || size == 0) {
        memcpy(dst, src, size);
        sys_icache_invalidate(dst, size);
        return true;
    }

    if (universal_jit_alias_backed) {
        ios_jit_sync_alias(src, dst, size);
        return true;
    }

    ios_jit_patch_universal_script_once();
    if (ios_jit_try_direct_rx_copy(dst, src, size)) {
        return true;
    }

    copy_index = ++copy_count;
    ret = UINT64_MAX;
    for (attempt = 1; attempt <= 4; attempt++) {
        size_t mismatch;

        ret = jit26_copy_code(dst, src, size);
        ios_jit_sync_executable(dst, size);
        mismatch = ios_jit_first_mismatch(dst, src, size);
        if (mismatch == SIZE_MAX) {
            if (ret != 0) {
                fprintf(stderr,
                        "xemu-ios: Universal.js copy verified despite ret #%" PRIu64
                        " attempt=%d dst=%p src=%p size=%zu ret=%" PRIu64 "\n",
                        copy_index, attempt, dst, src, size, ret);
            }
            ret = 0;
            break;
        }

        if (ret == 0) {
            ret = 2;
            fprintf(stderr,
                    "xemu-ios: Universal.js copy verify mismatch #%" PRIu64
                    " attempt=%d dst=%p src=%p size=%zu off=%zu "
                    "got=%02x expected=%02x\n",
                    copy_index, attempt, dst, src, size, mismatch,
                    ((const uint8_t *)dst)[mismatch],
                    ((const uint8_t *)src)[mismatch]);
        }
        if (ret != 0) {
            if (ret == (uintptr_t)dst) {
                const char *repatch = getenv("XEMU_IOS_REPATCH_ON_DST");

                fprintf(stderr,
                        "xemu-ios: Universal.js copy returned dst #%" PRIu64
                        " attempt=%d dst=%p src=%p size=%zu\n",
                        copy_index, attempt, dst, src, size);
                if (repatch != NULL && g_ascii_strcasecmp(repatch, "1") == 0) {
                    fprintf(stderr,
                            "xemu-ios: Universal.js copy returned dst #%" PRIu64
                            " attempt=%d; re-sending command patch\n",
                            copy_index, attempt);
                    ios_jit_repatch_universal_script();
                }
            }
            fprintf(stderr,
                    "xemu-ios: Universal.js copy retry #%" PRIu64
                    " attempt=%d dst=%p src=%p size=%zu ret=%" PRIu64 "\n",
                    copy_index, attempt, dst, src, size, ret);
            g_usleep(1000);
        }
    }
    if (ret != 0 || copy_index <= 32 || (copy_index % 1024) == 0 ||
        size >= 65536 || attempt > 1) {
        fprintf(stderr,
                "xemu-ios: Universal.js copy code #%" PRIu64
                " dst=%p src=%p size=%zu ret=%" PRIu64 " attempts=%d\n",
                copy_index, dst, src, size, ret, MIN(attempt, 4));
    }
    if (ret == 0) {
        return true;
    }
    return false;
#else
    memcpy(dst, src, size);
    return true;
#endif
}

bool xemu_ios_universal_jit_probe_split(void *rw_addr, void *rx_addr)
{
#if XEMU_IOS_UNIVERSAL_JIT_BRK
    if (!xemu_ios_universal_jit_is_enabled()) {
        return true;
    }

    ios_jit_write_probe(rw_addr);
    if (universal_jit_alias_backed) {
        ios_jit_sync_alias((char *)rw_addr + 4, (char *)rx_addr + 4, 12);
        ios_jit_call_probe(rx_addr);
        return true;
    }
    if (!xemu_ios_universal_jit_copy_code((char *)rx_addr + 4,
                                          (char *)rw_addr + 4, 12)) {
        warn_report("Universal.js JIT probe copy failed");
        return false;
    }
    ios_jit_call_probe(rx_addr);
#endif
    return true;
}
