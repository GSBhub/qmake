/* qmdummy: example out-of-tree target built by qmake. */
#include "qemu/osdep.h"
#include "qemu/qemu-print.h"
#include "cpu.h"
#include "exec/helper-proto.h"
#include "exec/cpu-common.h"
#include "accel/tcg/cpu-ldst.h"
#include "system/runstate.h"

void helper_halt(CPUQmDummyState *env)
{
    CPUState *cs = env_cpu(env);

    qemu_printf("qmdummy: halt at pc=0x%08" PRIx32 "\n", env->pc);
    qemu_system_shutdown_request(SHUTDOWN_CAUSE_GUEST_SHUTDOWN);
    cs->halted = 1;
    cs->exception_index = EXCP_HLT;
    cpu_loop_exit(cs);
}
