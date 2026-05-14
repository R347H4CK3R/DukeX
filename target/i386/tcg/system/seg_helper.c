/*
 *  x86 segmentation related helpers: (system-only code)
 *  TSS, interrupts, system calls, jumps and call/task gates, descriptors
 *
 *  Copyright (c) 2003 Fabrice Bellard
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

#include "qemu/osdep.h"
#include "qemu/log.h"
#include "qemu/main-loop.h"
#include "cpu.h"
#include "exec/helper-proto.h"
#include "accel/tcg/cpu-ldst.h"
#include "tcg/helper-tcg.h"
#include "../seg_helper.h"

#ifdef CONFIG_IOS
static void ios_x86_log_exec_interrupt(CPUState *cs, CPUX86State *env,
                                       const char *phase, int raw,
                                       int pending, int intno)
{
    static int trace_enabled = -1;
    static uint64_t count;
    static int64_t last_log_us;
    uint64_t pc = (uint64_t)(env->eip + env->segs[R_CS].base);
    bool low_boot_pc = pc >= 0x0000000000400000ULL &&
                       pc < 0x0000000000410000ULL;
    int64_t now;

    if (trace_enabled < 0) {
        const char *value = getenv("XEMU_IOS_IRQ_TRACE");
        trace_enabled = value && g_str_equal(value, "1");
    }
    if (!trace_enabled ||
        (!(raw & CPU_INTERRUPT_HARD) && pending != CPU_INTERRUPT_HARD)) {
        return;
    }

    count++;
    if (count > 32 && (count % 4096) != 0 && intno >= 0 && !low_boot_pc) {
        return;
    }
    now = g_get_monotonic_time();
    if (count > 32 && (count % 4096) != 0 &&
        now - last_log_us < 500 * 1000) {
        return;
    }
    last_log_us = now;

    fprintf(stderr,
            "xemu_ios: irq exec %s #%" PRIu64
            " raw=0x%x pending=0x%x intno=%d pc=0x%016" PRIx64
            " eflags=0x%08" PRIx64 " hflags=0x%08x hflags2=0x%08x"
            " eax=0x%08" PRIx64 " ebx=0x%08" PRIx64
            " ecx=0x%08" PRIx64 " edx=0x%08" PRIx64
            " esi=0x%08" PRIx64 " edi=0x%08" PRIx64
            " esp=0x%08" PRIx64 " ebp=0x%08" PRIx64 "\n",
            phase, count, raw, pending, intno, pc,
            (uint64_t)env->eflags, env->hflags, env->hflags2,
            (uint64_t)env->regs[R_EAX], (uint64_t)env->regs[R_EBX],
            (uint64_t)env->regs[R_ECX], (uint64_t)env->regs[R_EDX],
            (uint64_t)env->regs[R_ESI], (uint64_t)env->regs[R_EDI],
            (uint64_t)env->regs[R_ESP], (uint64_t)env->regs[R_EBP]);
}

static void ios_x86_log_hard_vector(CPUState *cs, CPUX86State *env,
                                    int raw, int intno)
{
    static int trace_enabled = -1;
    static uint64_t count;
    static int64_t last_log_us;
    uint64_t pc = (uint64_t)(env->eip + env->segs[R_CS].base);
    int64_t now = g_get_monotonic_time();

    if (trace_enabled < 0) {
        const char *value = getenv("XEMU_IOS_IRQ_TRACE");
        trace_enabled = value && g_str_equal(value, "1");
    }
    if (!trace_enabled) {
        return;
    }

    count++;
    if (count > 64 && intno >= 0 && (count % 4096) != 0 &&
        now - last_log_us < G_USEC_PER_SEC) {
        return;
    }
    last_log_us = now;

    fprintf(stderr,
            "xemu_ios: hard irq vector #%" PRIu64
            " raw=0x%x intno=%d pc=0x%016" PRIx64
            " eflags=0x%08" PRIx64 " hflags=0x%08x hflags2=0x%08x"
            " exit=%d irq=0x%x\n",
            count, raw, intno, pc, (uint64_t)env->eflags,
            env->hflags, env->hflags2, qatomic_read(&cs->exit_request),
            qatomic_read(&cs->interrupt_request));
}
#endif

void helper_syscall(CPUX86State *env, int next_eip_addend)
{
    int selector;

    if (!(env->efer & MSR_EFER_SCE)) {
        raise_exception_err_ra(env, EXCP06_ILLOP, 0, GETPC());
    }
    selector = (env->star >> 32) & 0xffff;
#ifdef TARGET_X86_64
    if (env->hflags & HF_LMA_MASK) {
        int code64;

        env->regs[R_ECX] = env->eip + next_eip_addend;
        env->regs[11] = cpu_compute_eflags(env) & ~RF_MASK;

        code64 = env->hflags & HF_CS64_MASK;

        env->eflags &= ~(env->fmask | RF_MASK);
        cpu_load_eflags(env, env->eflags, 0);
        cpu_x86_load_seg_cache(env, R_CS, selector & 0xfffc,
                           0, 0xffffffff,
                               DESC_G_MASK | DESC_P_MASK |
                               DESC_S_MASK |
                               DESC_CS_MASK | DESC_R_MASK | DESC_A_MASK |
                               DESC_L_MASK);
        cpu_x86_load_seg_cache(env, R_SS, (selector + 8) & 0xfffc,
                               0, 0xffffffff,
                               DESC_G_MASK | DESC_B_MASK | DESC_P_MASK |
                               DESC_S_MASK |
                               DESC_W_MASK | DESC_A_MASK);
        if (code64) {
            env->eip = env->lstar;
        } else {
            env->eip = env->cstar;
        }
    } else
#endif
    {
        env->regs[R_ECX] = (uint32_t)(env->eip + next_eip_addend);

        env->eflags &= ~(IF_MASK | RF_MASK | VM_MASK);
        cpu_x86_load_seg_cache(env, R_CS, selector & 0xfffc,
                           0, 0xffffffff,
                               DESC_G_MASK | DESC_B_MASK | DESC_P_MASK |
                               DESC_S_MASK |
                               DESC_CS_MASK | DESC_R_MASK | DESC_A_MASK);
        cpu_x86_load_seg_cache(env, R_SS, (selector + 8) & 0xfffc,
                               0, 0xffffffff,
                               DESC_G_MASK | DESC_B_MASK | DESC_P_MASK |
                               DESC_S_MASK |
                               DESC_W_MASK | DESC_A_MASK);
        env->eip = (uint32_t)env->star;
    }
}

void handle_even_inj(CPUX86State *env, int intno, int is_int,
                     int error_code, int is_hw, int rm)
{
    CPUState *cs = env_cpu(env);
    uint32_t event_inj = x86_ldl_phys(cs, env->vm_vmcb + offsetof(struct vmcb,
                                                          control.event_inj));

    if (!(event_inj & SVM_EVTINJ_VALID)) {
        int type;

        if (is_int) {
            type = SVM_EVTINJ_TYPE_SOFT;
        } else {
            type = SVM_EVTINJ_TYPE_EXEPT;
        }
        event_inj = intno | type | SVM_EVTINJ_VALID;
        if (!rm && exception_has_error_code(intno)) {
            event_inj |= SVM_EVTINJ_VALID_ERR;
            x86_stl_phys(cs, env->vm_vmcb + offsetof(struct vmcb,
                                             control.event_inj_err),
                     error_code);
        }
        x86_stl_phys(cs,
                 env->vm_vmcb + offsetof(struct vmcb, control.event_inj),
                 event_inj);
    }
}

void x86_cpu_do_interrupt(CPUState *cs)
{
    X86CPU *cpu = X86_CPU(cs);
    CPUX86State *env = &cpu->env;

    if (cs->exception_index == EXCP_VMEXIT) {
        assert(env->old_exception == -1);
        do_vmexit(env);
    } else {
        do_interrupt_all(cpu, cs->exception_index,
                         env->exception_is_int,
                         env->error_code,
                         env->exception_next_eip, 0);
        /* successfully delivered */
        env->old_exception = -1;
    }
}

bool x86_cpu_exec_halt(CPUState *cpu)
{
    X86CPU *x86_cpu = X86_CPU(cpu);
    CPUX86State *env = &x86_cpu->env;

    if (cpu_test_interrupt(cpu, CPU_INTERRUPT_POLL)) {
        bql_lock();
        apic_poll_irq(x86_cpu->apic_state);
        cpu_reset_interrupt(cpu, CPU_INTERRUPT_POLL);
        bql_unlock();
    }

    if (!cpu_has_work(cpu)) {
        return false;
    }

    /* Complete HLT instruction.  */
    if (env->eflags & TF_MASK) {
        env->dr[6] |= DR6_BS;
        do_interrupt_all(x86_cpu, EXCP01_DB, 0, 0, env->eip, 0);
    }
    return true;
}

bool x86_need_replay_interrupt(int interrupt_request)
{
    /*
     * CPU_INTERRUPT_POLL is a virtual event which gets converted into a
     * "real" interrupt event later. It does not need to be recorded for
     * replay purposes.
     */
    return !(interrupt_request & CPU_INTERRUPT_POLL);
}

bool x86_cpu_exec_interrupt(CPUState *cs, int interrupt_request)
{
    X86CPU *cpu = X86_CPU(cs);
    CPUX86State *env = &cpu->env;
    int raw_interrupt_request = interrupt_request;
    int intno;

    interrupt_request = x86_cpu_pending_interrupt(cs, interrupt_request);
    if (!interrupt_request) {
#ifdef CONFIG_IOS
        ios_x86_log_exec_interrupt(cs, env, "none", raw_interrupt_request,
                                   interrupt_request, -1);
#endif
        return false;
    }

#ifdef CONFIG_IOS
    ios_x86_log_exec_interrupt(cs, env, "selected", raw_interrupt_request,
                               interrupt_request, -1);
#endif

    /* Don't process multiple interrupt requests in a single call.
     * This is required to make icount-driven execution deterministic.
     */
    switch (interrupt_request) {
    case CPU_INTERRUPT_POLL:
        cpu_reset_interrupt(cs, CPU_INTERRUPT_POLL);
        apic_poll_irq(cpu->apic_state);
        break;
    case CPU_INTERRUPT_SIPI:
        cpu_reset_interrupt(cs, CPU_INTERRUPT_SIPI);
        do_cpu_sipi(cpu);
        break;
    case CPU_INTERRUPT_SMI:
        cpu_svm_check_intercept_param(env, SVM_EXIT_SMI, 0, 0);
        cpu_reset_interrupt(cs, CPU_INTERRUPT_SMI);
        do_smm_enter(cpu);
        break;
    case CPU_INTERRUPT_NMI:
        cpu_svm_check_intercept_param(env, SVM_EXIT_NMI, 0, 0);
        cpu_reset_interrupt(cs, CPU_INTERRUPT_NMI);
        env->hflags2 |= HF2_NMI_MASK;
        do_interrupt_x86_hardirq(env, EXCP02_NMI, 1);
        break;
    case CPU_INTERRUPT_MCE:
        cpu_reset_interrupt(cs, CPU_INTERRUPT_MCE);
        do_interrupt_x86_hardirq(env, EXCP12_MCHK, 0);
        break;
    case CPU_INTERRUPT_HARD:
        cpu_svm_check_intercept_param(env, SVM_EXIT_INTR, 0, 0);
        cpu_reset_interrupt(cs, CPU_INTERRUPT_HARD | CPU_INTERRUPT_VIRQ);
        intno = cpu_get_pic_interrupt(env);
#ifdef CONFIG_IOS
        ios_x86_log_hard_vector(cs, env, raw_interrupt_request, intno);
        ios_x86_log_exec_interrupt(cs, env, "hard-vector",
                                   raw_interrupt_request,
                                   interrupt_request, intno);
#endif
        qemu_log_mask(CPU_LOG_INT,
                      "Servicing hardware INT=0x%02x\n", intno);
        do_interrupt_x86_hardirq(env, intno, 1);
        break;
    case CPU_INTERRUPT_VIRQ:
        cpu_svm_check_intercept_param(env, SVM_EXIT_VINTR, 0, 0);
        intno = x86_ldl_phys(cs, env->vm_vmcb
                             + offsetof(struct vmcb, control.int_vector));
        qemu_log_mask(CPU_LOG_INT,
                      "Servicing virtual hardware INT=0x%02x\n", intno);
        do_interrupt_x86_hardirq(env, intno, 1);
        cpu_reset_interrupt(cs, CPU_INTERRUPT_VIRQ);
        env->int_ctl &= ~V_IRQ_MASK;
        break;
    }

    /* Ensure that no TB jump will be modified as the program flow was changed.  */
    return true;
}

/* check if Port I/O is allowed in TSS */
void helper_check_io(CPUX86State *env, uint32_t addr, uint32_t size)
{
    uintptr_t retaddr = GETPC();
    uint32_t io_offset, val, mask;

    /* TSS must be a valid 32 bit one */
    if (!(env->tr.flags & DESC_P_MASK) ||
        ((env->tr.flags >> DESC_TYPE_SHIFT) & 0xf) != 9 ||
        env->tr.limit < 103) {
        goto fail;
    }
    io_offset = cpu_lduw_kernel_ra(env, env->tr.base + 0x66, retaddr);
    io_offset += (addr >> 3);
    /* Note: the check needs two bytes */
    if ((io_offset + 1) > env->tr.limit) {
        goto fail;
    }
    val = cpu_lduw_kernel_ra(env, env->tr.base + io_offset, retaddr);
    val >>= (addr & 7);
    mask = (1 << size) - 1;
    /* all bits must be zero to allow the I/O */
    if ((val & mask) != 0) {
    fail:
        raise_exception_err_ra(env, EXCP0D_GPF, 0, retaddr);
    }
}
