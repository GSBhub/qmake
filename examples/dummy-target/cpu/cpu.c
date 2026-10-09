/* qmdummy: example out-of-tree target built by qmake. */
#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu/qemu-print.h"
#include "cpu.h"
#include "exec/translation-block.h"
#include "exec/cputlb.h"
#include "exec/page-protection.h"
#include "exec/target_page.h"
#include "accel/tcg/cpu-ops.h"
#include "hw/core/sysemu-cpu-ops.h"

static void qmdummy_cpu_set_pc(CPUState *cs, vaddr value)
{
    cpu_env(cs)->pc = value;
}

static vaddr qmdummy_cpu_get_pc(CPUState *cs)
{
    return cpu_env(cs)->pc;
}

static bool qmdummy_cpu_has_work(CPUState *cs)
{
    return false;
}

static int qmdummy_cpu_mmu_index(CPUState *cs, bool ifetch)
{
    return 0;
}

static TCGTBCPUState qmdummy_get_tb_cpu_state(CPUState *cs)
{
    return (TCGTBCPUState){ .pc = cpu_env(cs)->pc };
}

static void qmdummy_cpu_synchronize_from_tb(CPUState *cs,
                                            const TranslationBlock *tb)
{
    cpu_env(cs)->pc = tb->pc;
}

static void qmdummy_restore_state_to_opc(CPUState *cs,
                                         const TranslationBlock *tb,
                                         const uint64_t *data)
{
    cpu_env(cs)->pc = data[0];
}

static bool qmdummy_cpu_exec_interrupt(CPUState *cs, int interrupt_request)
{
    return false;
}

static bool qmdummy_cpu_tlb_fill(CPUState *cs, vaddr address, int size,
                                 MMUAccessType access_type, int mmu_idx,
                                 bool probe, uintptr_t retaddr)
{
    address &= TARGET_PAGE_MASK;
    tlb_set_page(cs, address, address, PAGE_READ | PAGE_WRITE | PAGE_EXEC,
                 mmu_idx, TARGET_PAGE_SIZE);
    return true;
}

static hwaddr qmdummy_cpu_get_phys_page_debug(CPUState *cs, vaddr addr)
{
    return addr;
}

static void qmdummy_cpu_reset_hold(Object *obj, ResetType type)
{
    QmDummyCPUClass *mcc = QMDUMMY_CPU_GET_CLASS(obj);

    if (mcc->parent_phases.hold) {
        mcc->parent_phases.hold(obj, type);
    }
    cpu_env(CPU(obj))->pc = 0;
}

static void qmdummy_cpu_realizefn(DeviceState *dev, Error **errp)
{
    CPUState *cs = CPU(dev);
    QmDummyCPUClass *mcc = QMDUMMY_CPU_GET_CLASS(dev);
    Error *local_err = NULL;

    cpu_exec_realizefn(cs, &local_err);
    if (local_err != NULL) {
        error_propagate(errp, local_err);
        return;
    }
    qemu_init_vcpu(cs);
    cpu_reset(cs);

    mcc->parent_realize(dev, errp);
}

static ObjectClass *qmdummy_cpu_class_by_name(const char *cpu_model)
{
    return object_class_by_name(TYPE_QMDUMMY_CPU);
}

static void qmdummy_cpu_dump_state(CPUState *cs, FILE *f, int flags)
{
    qemu_fprintf(f, "PC: %08x\n", cpu_env(cs)->pc);
}

static const struct SysemuCPUOps qmdummy_sysemu_ops = {
    .has_work = qmdummy_cpu_has_work,
    .get_phys_page_debug = qmdummy_cpu_get_phys_page_debug,
};

static const TCGCPUOps qmdummy_tcg_ops = {
    .guest_default_memory_order = 0,
    .mttcg_supported = false,
    .initialize = qmdummy_cpu_tcg_init,
    .translate_code = qmdummy_cpu_translate_code,
    .get_tb_cpu_state = qmdummy_get_tb_cpu_state,
    .synchronize_from_tb = qmdummy_cpu_synchronize_from_tb,
    .restore_state_to_opc = qmdummy_restore_state_to_opc,
    .mmu_index = qmdummy_cpu_mmu_index,
    .cpu_exec_interrupt = qmdummy_cpu_exec_interrupt,
    .cpu_exec_halt = qmdummy_cpu_has_work,
    .cpu_exec_reset = cpu_reset,
    .tlb_fill = qmdummy_cpu_tlb_fill,
    .pointer_wrap = cpu_pointer_wrap_uint32,
};

static void qmdummy_cpu_class_init(ObjectClass *oc, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(oc);
    CPUClass *cc = CPU_CLASS(oc);
    QmDummyCPUClass *mcc = QMDUMMY_CPU_CLASS(oc);
    ResettableClass *rc = RESETTABLE_CLASS(oc);

    device_class_set_parent_realize(dc, qmdummy_cpu_realizefn,
                                    &mcc->parent_realize);
    resettable_class_set_parent_phases(rc, NULL, qmdummy_cpu_reset_hold, NULL,
                                       &mcc->parent_phases);

    cc->class_by_name = qmdummy_cpu_class_by_name;
    cc->dump_state = qmdummy_cpu_dump_state;
    cc->set_pc = qmdummy_cpu_set_pc;
    cc->get_pc = qmdummy_cpu_get_pc;
    cc->sysemu_ops = &qmdummy_sysemu_ops;
    cc->tcg_ops = &qmdummy_tcg_ops;
}

static const TypeInfo qmdummy_cpu_type_info[] = {
    {
        .name = TYPE_QMDUMMY_CPU,
        .parent = TYPE_CPU,
        .instance_size = sizeof(QmDummyCPU),
        .instance_align = __alignof(QmDummyCPU),
        .class_size = sizeof(QmDummyCPUClass),
        .class_init = qmdummy_cpu_class_init,
    },
};

DEFINE_TYPES(qmdummy_cpu_type_info)
