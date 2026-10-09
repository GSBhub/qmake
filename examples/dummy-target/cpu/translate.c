/* qmdummy: example out-of-tree target built by qmake. */
#include "qemu/osdep.h"
#include "cpu.h"
#include "tcg/tcg-op.h"
#include "exec/helper-proto.h"
#include "exec/helper-gen.h"
#include "exec/translator.h"
#include "exec/translation-block.h"

#define HELPER_H "helper.h"
#include "exec/helper-info.c.inc"
#undef  HELPER_H

static TCGv_i32 cpu_pc;

void qmdummy_cpu_tcg_init(void)
{
    cpu_pc = tcg_global_mem_new_i32(tcg_env, offsetof(CPUQmDummyState, pc), "pc");
}

static void qmdummy_tr_init_disas_context(DisasContextBase *db, CPUState *cs)
{
}

static void qmdummy_tr_tb_start(DisasContextBase *db, CPUState *cs)
{
}

static void qmdummy_tr_insn_start(DisasContextBase *db, CPUState *cs)
{
    tcg_gen_insn_start(db->pc_next);
}

/* Every "instruction" is a halt: record the pc and leave the cpu loop. */
static void qmdummy_tr_translate_insn(DisasContextBase *db, CPUState *cs)
{
    tcg_gen_movi_i32(cpu_pc, db->pc_next);
    gen_helper_halt(tcg_env);
    db->pc_next += 4;
    db->is_jmp = DISAS_NORETURN;
}

static void qmdummy_tr_tb_stop(DisasContextBase *db, CPUState *cs)
{
}

static const TranslatorOps qmdummy_tr_ops = {
    .init_disas_context = qmdummy_tr_init_disas_context,
    .tb_start           = qmdummy_tr_tb_start,
    .insn_start         = qmdummy_tr_insn_start,
    .translate_insn     = qmdummy_tr_translate_insn,
    .tb_stop            = qmdummy_tr_tb_stop,
};

void qmdummy_cpu_translate_code(CPUState *cs, TranslationBlock *tb,
                                int *max_insns, vaddr pc, void *host_pc)
{
    DisasContextBase db = { };

    translator_loop(cs, tb, max_insns, pc, host_pc, &qmdummy_tr_ops, &db);
}
