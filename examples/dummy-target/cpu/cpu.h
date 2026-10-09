/* qmdummy: example out-of-tree target built by qmake. */
#ifndef QMDUMMY_CPU_H
#define QMDUMMY_CPU_H

#include "cpu-qom.h"
#include "exec/cpu-common.h"
#include "exec/cpu-defs.h"
#include "exec/cpu-interrupt.h"

#ifdef CONFIG_USER_ONLY
#error "qmdummy does not support user mode"
#endif

#define CPU_RESOLVING_TYPE TYPE_QMDUMMY_CPU

typedef struct CPUArchState {
    uint32_t pc;
} CPUQmDummyState;

struct ArchCPU {
    CPUState parent_obj;
    CPUQmDummyState env;
};

struct QmDummyCPUClass {
    CPUClass parent_class;
    DeviceRealize parent_realize;
    ResettablePhases parent_phases;
};

void qmdummy_cpu_tcg_init(void);
void qmdummy_cpu_translate_code(CPUState *cs, TranslationBlock *tb,
                                int *max_insns, vaddr pc, void *host_pc);

#endif
