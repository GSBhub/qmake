/* qmdummy: example out-of-tree target built by qmake. */
#ifndef QMDUMMY_CPU_QOM_H
#define QMDUMMY_CPU_QOM_H

#include "hw/core/cpu.h"

#define TYPE_QMDUMMY_CPU "qmdummy-cpu"

OBJECT_DECLARE_CPU_TYPE(QmDummyCPU, QmDummyCPUClass, QMDUMMY_CPU)

#endif
