/*
 * QEMU Geforce NV2A implementation
 *
 * Copyright (c) 2012 espes
 * Copyright (c) 2015 Jannik Vogel
 * Copyright (c) 2018-2021 Matt Borgerson
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

#include "nv2a_int.h"

#define DEFINE_STUB(name, region_id) \
    uint64_t name ## _read(void *opaque, \
                           hwaddr addr, \
                           unsigned int size) \
    { \
        nv2a_reg_log_read(region_id, addr, size, 0); \
        return 0; \
    } \
    void name ## _write(void *opaque, \
                        hwaddr addr, \
                        uint64_t val, \
                        unsigned int size) \
    { \
        nv2a_reg_log_write(region_id, addr, size, val); \
    } \

DEFINE_STUB(prma, NV_PRMA)
DEFINE_STUB(pcounter, NV_PCOUNTER)
DEFINE_STUB(pvpe, NV_PVPE)
DEFINE_STUB(ptv, NV_PTV)
DEFINE_STUB(prmfb, NV_PRMFB)
// DEFINE_STUB(pramin, NV_PRAMIN)

#undef DEFINE_STUB

uint64_t pstraps_read(void *opaque, hwaddr addr, unsigned int size)
{
    uint64_t val = 0;
#ifdef CONFIG_IOS
    static bool ios_pstraps_env_checked;
    static bool ios_pstraps_override_enabled;
    static uint64_t ios_pstraps_override;
    static unsigned ios_pstraps_read_logs;

    if (!ios_pstraps_env_checked) {
        const char *override = g_getenv("XEMU_IOS_PSTRAPS_VALUE");

        ios_pstraps_env_checked = true;
        if (override && *override) {
            ios_pstraps_override = g_ascii_strtoull(override, NULL, 0);
            ios_pstraps_override_enabled = true;
            fprintf(stderr,
                    "xemu_ios: pstraps override enabled value=0x%016"
                    PRIx64 "\n",
                    ios_pstraps_override);
        }
    }

    if (ios_pstraps_override_enabled) {
        val = ios_pstraps_override;
    }

    if (ios_pstraps_read_logs < 48 || (ios_pstraps_read_logs % 1024) == 0) {
        fprintf(stderr,
                "xemu_ios: pstraps read[%u] addr=0x%" HWADDR_PRIx
                " size=%u val=0x%016" PRIx64 "\n",
                ios_pstraps_read_logs, addr, size, val);
    }
    ios_pstraps_read_logs++;
#endif

    nv2a_reg_log_read(NV_PSTRAPS, addr, size, val);
    return val;
}

void pstraps_write(void *opaque, hwaddr addr, uint64_t val, unsigned int size)
{
    nv2a_reg_log_write(NV_PSTRAPS, addr, size, val);
}
