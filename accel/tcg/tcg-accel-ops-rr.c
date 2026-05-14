/*
 * QEMU TCG Single Threaded vCPUs implementation
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
#include "qemu/lockable.h"
#include "system/tcg.h"
#include "system/replay.h"
#include "exec/icount.h"
#include "qemu/main-loop.h"
#include "qemu/notify.h"
#include "qemu/guest-random.h"
#include "exec/cpu-common.h"
#include "tcg/startup.h"
#include "tcg-accel-ops.h"
#include "tcg-accel-ops-rr.h"
#include "tcg-accel-ops-icount.h"

#ifdef CONFIG_IOS
static void ios_rr_watchdog_log(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    int len;

    va_start(ap, fmt);
    len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (len <= 0) {
        return;
    }
    if (len >= (int)sizeof(buf)) {
        len = (int)sizeof(buf) - 1;
    }
    (void)write(STDERR_FILENO, buf, len);
}

static bool ios_rr_return_trace_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        const char *env = getenv("XEMU_IOS_RR_RETURN_TRACE");
        enabled = env && strcmp(env, "0") != 0;
    }

    return enabled;
}

static gpointer ios_rr_watchdog_thread(gpointer opaque)
{
    CPUState *cpu = opaque;
    const char *mode = getenv("XEMU_IOS_TCG_WATCHDOG");
    bool kick_cpu = !mode || (g_ascii_strcasecmp(mode, "log") != 0 &&
                              g_ascii_strcasecmp(mode, "log-only") != 0);
    uint64_t ticks = 0;
    vaddr last_pc = 0;
    unsigned stable_ticks = 0;

    ios_rr_watchdog_log("xemu_ios: rr watchdog mode=%s\n",
                        kick_cpu ? "kick" : "log-only");
    g_usleep(10 * G_USEC_PER_SEC);

    for (;;) {
        vaddr pc = 0;

        g_usleep(250 * 1000);
        if (kick_cpu) {
            cpu_exit(cpu);
        }
        ticks++;

        if ((ticks % 4) != 0) {
            continue;
        }

        if (cpu->cc->get_pc) {
            pc = cpu->cc->get_pc(cpu);
        }

        if (pc == last_pc) {
            stable_ticks++;
        } else {
            last_pc = pc;
            stable_ticks = 0;
        }

        ios_rr_watchdog_log(
            "xemu_ios: rr watchdog tick cpu=%d ticks=%" PRIu64
            " pc=0x%016" VADDR_PRIx " stable=%u can_run=%d"
            " halted=%d stop=%d exit=%d irq=0x%x\n",
            cpu->cpu_index, ticks, pc, stable_ticks,
            cpu_can_run(cpu), cpu->halted, cpu->stop,
            qatomic_read(&cpu->exit_request),
            qatomic_read(&cpu->interrupt_request));
    }

    return NULL;
}

static void ios_rr_start_watchdog(CPUState *cpu)
{
    static gsize started;
    const char *mode = getenv("XEMU_IOS_TCG_WATCHDOG");

    if (mode && (g_ascii_strcasecmp(mode, "0") == 0 ||
                 g_ascii_strcasecmp(mode, "false") == 0 ||
                 g_ascii_strcasecmp(mode, "off") == 0 ||
                 g_ascii_strcasecmp(mode, "no") == 0)) {
        ios_rr_watchdog_log("xemu_ios: rr watchdog disabled cpu=%d\n",
                            cpu->cpu_index);
        return;
    }

    if (g_once_init_enter(&started)) {
        GThread *thread = g_thread_new("ios-rr-watchdog",
                                       ios_rr_watchdog_thread, cpu);
        g_thread_unref(thread);
        g_once_init_leave(&started, 1);
        ios_rr_watchdog_log("xemu_ios: rr watchdog started cpu=%d\n",
                            cpu->cpu_index);
    }
}
#endif

/* Kick all RR vCPUs */
void rr_kick_vcpu_thread(CPUState *unused)
{
    CPUState *cpu;

    CPU_FOREACH(cpu) {
        tcg_kick_vcpu_thread(cpu);
    };
}

/*
 * TCG vCPU kick timer
 *
 * The kick timer is responsible for moving single threaded vCPU
 * emulation on to the next vCPU. If more than one vCPU is running a
 * timer event we force a cpu->exit so the next vCPU can get
 * scheduled.
 *
 * The timer is removed if all vCPUs are idle and restarted again once
 * idleness is complete.
 */

static QEMUTimer *rr_kick_vcpu_timer;
static CPUState *rr_current_cpu;

static inline int64_t rr_next_kick_time(void)
{
    return qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) + TCG_KICK_PERIOD;
}

/* Kick the currently round-robin scheduled vCPU to next */
static void rr_kick_next_cpu(void)
{
    CPUState *cpu;
    do {
        cpu = qatomic_read(&rr_current_cpu);
        if (cpu) {
            cpu_exit(cpu);
        }
        /* Finish kicking this cpu before reading again.  */
        smp_mb();
    } while (cpu != qatomic_read(&rr_current_cpu));
}

static void rr_kick_thread(void *opaque)
{
    timer_mod(rr_kick_vcpu_timer, rr_next_kick_time());
    rr_kick_next_cpu();
}

static void rr_start_kick_timer(void)
{
    if (!rr_kick_vcpu_timer && CPU_NEXT(first_cpu)) {
        rr_kick_vcpu_timer = timer_new_ns(QEMU_CLOCK_VIRTUAL,
                                           rr_kick_thread, NULL);
    }
    if (rr_kick_vcpu_timer && !timer_pending(rr_kick_vcpu_timer)) {
        timer_mod(rr_kick_vcpu_timer, rr_next_kick_time());
    }
}

static void rr_stop_kick_timer(void)
{
    if (rr_kick_vcpu_timer && timer_pending(rr_kick_vcpu_timer)) {
        timer_del(rr_kick_vcpu_timer);
    }
}

static void rr_wait_io_event(void)
{
    CPUState *cpu;

    while (all_cpu_threads_idle()) {
        rr_stop_kick_timer();
        qemu_cond_wait_bql(first_cpu->halt_cond);
    }

    rr_start_kick_timer();

    CPU_FOREACH(cpu) {
        qemu_process_cpu_events_common(cpu);
    }
}

/*
 * Destroy any remaining vCPUs which have been unplugged and have
 * finished running
 */
static void rr_deal_with_unplugged_cpus(void)
{
    CPUState *cpu;

    CPU_FOREACH(cpu) {
        if (cpu->unplug && !cpu_can_run(cpu)) {
            tcg_cpu_destroy(cpu);
            break;
        }
    }
}

static void rr_force_rcu(Notifier *notify, void *data)
{
    rr_kick_next_cpu();
}

/*
 * Calculate the number of CPUs that we will process in a single iteration of
 * the main CPU thread loop so that we can fairly distribute the instruction
 * count across CPUs.
 *
 * The CPU count is cached based on the CPU list generation ID to avoid
 * iterating the list every time.
 */
static int rr_cpu_count(void)
{
    static unsigned int last_gen_id = ~0;
    static int cpu_count;
    CPUState *cpu;

    QEMU_LOCK_GUARD(&qemu_cpu_list_lock);

    if (cpu_list_generation_id_get() != last_gen_id) {
        cpu_count = 0;
        CPU_FOREACH(cpu) {
            ++cpu_count;
        }
        last_gen_id = cpu_list_generation_id_get();
    }

    return cpu_count;
}

/*
 * In the single-threaded case each vCPU is simulated in turn. If
 * there is more than a single vCPU we create a simple timer to kick
 * the vCPU and ensure we don't get stuck in a tight loop in one vCPU.
 * This is done explicitly rather than relying on side-effects
 * elsewhere.
 */

static void *rr_cpu_thread_fn(void *arg)
{
    Notifier force_rcu;
    CPUState *cpu = arg;

    assert(tcg_enabled());
    rcu_register_thread();
    force_rcu.notify = rr_force_rcu;
    rcu_add_force_rcu_notifier(&force_rcu);
    tcg_register_thread();

    bql_lock();
    qemu_thread_get_self(cpu->thread);

    cpu->thread_id = qemu_get_thread_id();
    cpu->neg.can_do_io = true;
    cpu_thread_signal_created(cpu);
    qemu_guest_random_seed_thread_part2(cpu->random_seed);
#ifdef CONFIG_IOS
    fprintf(stderr, "xemu_ios: rr cpu thread started cpu=%d tid=%" PRId64 "\n",
            cpu->cpu_index, (int64_t)cpu->thread_id);
    ios_rr_start_watchdog(cpu);
#endif

    /* wait for initial kick-off after machine start */
    while (cpu_is_stopped(first_cpu)) {
        qemu_cond_wait_bql(first_cpu->halt_cond);

        /* process any pending work */
        CPU_FOREACH(cpu) {
            current_cpu = cpu;
            qemu_process_cpu_events_common(cpu);
        }
    }

    rr_start_kick_timer();

    cpu = first_cpu;

    while (1) {
        /* Only used for icount_enabled() */
        int64_t cpu_budget = 0;

        if (cpu) {
            /*
             * This could even reset exit_request for all CPUs, but in practice
             * races between CPU exits and changes to "cpu" are so rare that
             * there's no advantage in doing so.
             */
            qatomic_set(&cpu->exit_request, false);
        }

        if (icount_enabled() && all_cpu_threads_idle()) {
            /*
             * When all cpus are sleeping (e.g in WFI), to avoid a deadlock
             * in the main_loop, wake it up in order to start the warp timer.
             */
            qemu_notify_event();
        }

        rr_wait_io_event();
        rr_deal_with_unplugged_cpus();

        bql_unlock();
        replay_mutex_lock();
        bql_lock();

        if (icount_enabled()) {
            int cpu_count = rr_cpu_count();

            /* Account partial waits to QEMU_CLOCK_VIRTUAL.  */
            icount_account_warp_timer();
            /*
             * Run the timers here.  This is much more efficient than
             * waking up the I/O thread and waiting for completion.
             */
            icount_handle_deadline();

            cpu_budget = icount_percpu_budget(cpu_count);
        }

        replay_mutex_unlock();

        if (!cpu) {
            cpu = first_cpu;
        }

        while (cpu && cpu_work_list_empty(cpu)) {
            /*
             * Store rr_current_cpu before evaluating cpu->exit_request.
             * Pairs with rr_kick_next_cpu().
             */
            qatomic_set_mb(&rr_current_cpu, cpu);

            /* Pairs with store-release in cpu_exit.  */
            if (qatomic_load_acquire(&cpu->exit_request)) {
                break;
            }
            current_cpu = cpu;

            qemu_clock_enable(QEMU_CLOCK_VIRTUAL,
                              (cpu->singlestep_enabled & SSTEP_NOTIMER) == 0);

            if (cpu_can_run(cpu)) {
                int r;
#ifdef CONFIG_IOS
                static int64_t last_return_log_us;
#endif

                bql_unlock();
                if (icount_enabled()) {
                    icount_prepare_for_run(cpu, cpu_budget);
                }
                r = tcg_cpu_exec(cpu);
                if (icount_enabled()) {
                    icount_process_data(cpu);
                }
                bql_lock();

#ifdef CONFIG_IOS
                int64_t now = g_get_monotonic_time();
                if (ios_rr_return_trace_enabled() &&
                    (now - last_return_log_us >= G_USEC_PER_SEC ||
                     r != EXCP_INTERRUPT)) {
                    last_return_log_us = now;
                    fprintf(stderr,
                            "xemu_ios: rr tcg_cpu_exec returned cpu=%d"
                            " r=%d halted=%d irq=0x%x exit=%d\n",
                            cpu->cpu_index, r, cpu->halted,
                            qatomic_read(&cpu->interrupt_request),
                            qatomic_read(&cpu->exit_request));
                }
#endif

                if (r == EXCP_DEBUG) {
                    cpu_handle_guest_debug(cpu);
                    break;
                } else if (r == EXCP_ATOMIC) {
                    bql_unlock();
                    cpu_exec_step_atomic(cpu);
                    bql_lock();
                    break;
                }
            } else if (cpu->stop) {
                if (cpu->unplug) {
                    cpu = CPU_NEXT(cpu);
                }
                break;
            }

            cpu = CPU_NEXT(cpu);
        } /* while (cpu && !cpu->exit_request).. */

        /* Does not need a memory barrier because a spurious wakeup is okay.  */
        qatomic_set(&rr_current_cpu, NULL);
    }

    g_assert_not_reached();
}

void rr_start_vcpu_thread(CPUState *cpu)
{
    char thread_name[VCPU_THREAD_NAME_SIZE];
    static QemuCond *single_tcg_halt_cond;
    static QemuThread *single_tcg_cpu_thread;

    g_assert(tcg_enabled());
    tcg_cpu_init_cflags(cpu, false);

    if (!single_tcg_cpu_thread) {
        single_tcg_halt_cond = cpu->halt_cond;
        single_tcg_cpu_thread = cpu->thread;

        /* share a single thread for all cpus with TCG */
        snprintf(thread_name, VCPU_THREAD_NAME_SIZE, "ALL CPUs/TCG");
        qemu_thread_create(cpu->thread, thread_name,
                           rr_cpu_thread_fn,
                           cpu, QEMU_THREAD_JOINABLE);
    } else {
        /* we share the thread, dump spare data */
        g_free(cpu->thread);
        qemu_cond_destroy(cpu->halt_cond);
        g_free(cpu->halt_cond);
        cpu->thread = single_tcg_cpu_thread;
        cpu->halt_cond = single_tcg_halt_cond;

        /* copy the stuff done at start of rr_cpu_thread_fn */
        cpu->thread_id = first_cpu->thread_id;
        cpu->neg.can_do_io = 1;
        cpu->created = true;
    }
}
