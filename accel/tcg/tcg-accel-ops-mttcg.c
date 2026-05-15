/*
 * QEMU TCG Multi Threaded vCPUs implementation
 *
 * Copyright (c) 2003-2008 Fabrice Bellard
 * Copyright (c) 2014 Red Hat Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"
#include "system/tcg.h"
#include "system/replay.h"
#include "exec/icount.h"
#include "qemu/main-loop.h"
#include "qemu/notify.h"
#include "qemu/guest-random.h"
#include "hw/boards.h"
#include "tcg/startup.h"
#include "tcg-accel-ops.h"
#include "tcg-accel-ops-mttcg.h"

typedef struct MttcgForceRcuNotifier {
    Notifier notifier;
    CPUState *cpu;
} MttcgForceRcuNotifier;

static void do_nothing(CPUState *cpu, run_on_cpu_data d)
{
}

static void mttcg_force_rcu(Notifier *notify, void *data)
{
    CPUState *cpu = container_of(notify, MttcgForceRcuNotifier, notifier)->cpu;

    /*
     * Called with rcu_registry_lock held, using async_run_on_cpu() ensures
     * that there are no deadlocks.
     */
    async_run_on_cpu(cpu, do_nothing, RUN_ON_CPU_NULL);
}

#ifdef CONFIG_IOS
static void ios_tcg_watchdog_dump_bytes(CPUState *cpu, vaddr pc)
{
    uint8_t bytes[64];
    vaddr base = pc >= 16 ? pc - 16 : pc;
    g_autoptr(GString) line = g_string_new(NULL);
    int ret;

    ret = cpu_memory_rw_debug(cpu, base, bytes, sizeof(bytes), false);
    if (ret != 0) {
        fprintf(stderr,
                "xemu_ios: tcg watchdog bytes pc=0x%016" VADDR_PRIx
                " base=0x%016" VADDR_PRIx " unavailable ret=%d\n",
                pc, base, ret);
        return;
    }

    for (size_t i = 0; i < sizeof(bytes); i++) {
        g_string_append_printf(line, " %02x", bytes[i]);
    }

    fprintf(stderr,
            "xemu_ios: tcg watchdog bytes pc=0x%016" VADDR_PRIx
            " base=0x%016" VADDR_PRIx "%s\n",
            pc, base, line->str);

}

static gpointer ios_tcg_watchdog_thread(gpointer opaque)
{
    CPUState *cpu = opaque;
    const char *mode = getenv("XEMU_IOS_TCG_WATCHDOG");
    bool kick_cpu = !mode || (g_ascii_strcasecmp(mode, "log") != 0 &&
                              g_ascii_strcasecmp(mode, "log-only") != 0);
    uint64_t kicks = 0;
    vaddr last_pc = 0;
    vaddr dumped_pc = 0;
    unsigned stable_pc_logs = 0;

    fprintf(stderr, "xemu_ios: tcg watchdog mode=%s\n",
            kick_cpu ? "kick" : "log-only");
    g_usleep(10 * G_USEC_PER_SEC);
    for (;;) {
        vaddr pc = 0;

        g_usleep(250 * 1000);
        if (kick_cpu) {
            cpu_exit(cpu);
        }
        kicks++;

        if ((kicks % 4) == 0) {
            if (cpu->cc->get_pc) {
                pc = cpu->cc->get_pc(cpu);
            }
            if (pc == last_pc) {
                stable_pc_logs++;
            } else {
                last_pc = pc;
                stable_pc_logs = 0;
            }
            fprintf(stderr,
                    "xemu_ios: tcg watchdog kick cpu=%d kicks=%" PRIu64
                    " pc=0x%016" VADDR_PRIx " exit=%d irq=0x%x\n",
                    cpu->cpu_index, kicks, pc,
                    qatomic_read(&cpu->exit_request),
                    qatomic_read(&cpu->interrupt_request));
            if (stable_pc_logs == 4 && dumped_pc != pc) {
                dumped_pc = pc;
                ios_tcg_watchdog_dump_bytes(cpu, pc);
            }
        }
    }

    return NULL;
}

static void ios_tcg_start_watchdog(CPUState *cpu)
{
    static gsize started;
    const char *mode = getenv("XEMU_IOS_TCG_WATCHDOG");

    if (mode && (g_ascii_strcasecmp(mode, "0") == 0 ||
                 g_ascii_strcasecmp(mode, "false") == 0 ||
                 g_ascii_strcasecmp(mode, "off") == 0 ||
                 g_ascii_strcasecmp(mode, "no") == 0)) {
        fprintf(stderr, "xemu_ios: tcg watchdog disabled cpu=%d\n",
                cpu->cpu_index);
        return;
    }

    if (g_once_init_enter(&started)) {
        GThread *thread = g_thread_new("ios-tcg-watchdog",
                                       ios_tcg_watchdog_thread, cpu);
        g_thread_unref(thread);
        g_once_init_leave(&started, 1);
        fprintf(stderr, "xemu_ios: tcg watchdog started cpu=%d\n",
                cpu->cpu_index);
    }
}
#endif

/*
 * In the multi-threaded case each vCPU has its own thread. The TLS
 * variable current_cpu can be used deep in the code to find the
 * current CPUState for a given thread.
 */

static void *mttcg_cpu_thread_fn(void *arg)
{
    MttcgForceRcuNotifier force_rcu;
    CPUState *cpu = arg;

    assert(tcg_enabled());
    g_assert(!icount_enabled());

    rcu_register_thread();
    force_rcu.notifier.notify = mttcg_force_rcu;
    force_rcu.cpu = cpu;
    rcu_add_force_rcu_notifier(&force_rcu.notifier);
    tcg_register_thread();

    bql_lock();
    qemu_thread_get_self(cpu->thread);

    cpu->thread_id = qemu_get_thread_id();
    cpu->neg.can_do_io = true;
    current_cpu = cpu;
    cpu_thread_signal_created(cpu);
    qemu_guest_random_seed_thread_part2(cpu->random_seed);
#ifdef CONFIG_IOS
    fprintf(stderr, "xemu_ios: mttcg cpu thread started cpu=%d tid=%" PRId64 "\n",
            cpu->cpu_index, (int64_t)cpu->thread_id);
    ios_tcg_start_watchdog(cpu);
#endif

    do {
        qemu_process_cpu_events(cpu);

        if (cpu_can_run(cpu)) {
            int r;
#ifdef CONFIG_IOS
            static int64_t last_return_log_us;
#endif
            bql_unlock();
            r = tcg_cpu_exec(cpu);
            bql_lock();
#ifdef CONFIG_IOS
            int64_t now = g_get_monotonic_time();
            if (now - last_return_log_us >= G_USEC_PER_SEC || r != EXCP_INTERRUPT) {
                last_return_log_us = now;
                fprintf(stderr,
                        "xemu_ios: tcg_cpu_exec returned cpu=%d r=%d halted=%d irq=0x%x\n",
                        cpu->cpu_index, r, cpu->halted,
                        qatomic_read(&cpu->interrupt_request));
            }
#endif
            switch (r) {
            case EXCP_DEBUG:
                cpu_handle_guest_debug(cpu);
                break;
            case EXCP_HALTED:
                /*
                 * Usually cpu->halted is set, but may have already been
                 * reset by another thread by the time we arrive here.
                 */
                break;
            case EXCP_ATOMIC:
                bql_unlock();
                cpu_exec_step_atomic(cpu);
                bql_lock();
            default:
                /* Ignore everything else? */
                break;
            }
        }
    } while (!cpu->unplug || cpu_can_run(cpu));

    tcg_cpu_destroy(cpu);
    bql_unlock();
    rcu_remove_force_rcu_notifier(&force_rcu.notifier);
    rcu_unregister_thread();
    return NULL;
}

void mttcg_start_vcpu_thread(CPUState *cpu)
{
    char thread_name[VCPU_THREAD_NAME_SIZE];

    g_assert(tcg_enabled());
    tcg_cpu_init_cflags(cpu, current_machine->smp.max_cpus > 1);

    /* create a thread per vCPU with TCG (MTTCG) */
    snprintf(thread_name, VCPU_THREAD_NAME_SIZE, "CPU %d/TCG",
             cpu->cpu_index);

    qemu_thread_create(cpu->thread, thread_name, mttcg_cpu_thread_fn,
                       cpu, QEMU_THREAD_JOINABLE);
}
