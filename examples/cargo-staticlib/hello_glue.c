/*
 * C glue for the qmake LANG CARGO example: compiled by QEMU's meson with QEMU's
 * flags, it calls into the Rust staticlib. Set QMAKE_CARGO_HELLO=1 to see it.
 */
#include "qemu/osdep.h"
#include "qemu/module.h"

uint32_t qmake_cargo_answer(void);
void qmake_cargo_greeting(char *buf, size_t len);

static void qmake_cargo_hello_init(void)
{
    char buf[64];

    if (!getenv("QMAKE_CARGO_HELLO")) {
        return;
    }
    qmake_cargo_greeting(buf, sizeof(buf));
    /* type_init runs before the monitor exists, so no qemu_printf here. */
    fprintf(stderr, "qmake-cargo-hello: %s (answer=%u)\n", buf, qmake_cargo_answer());
}

type_init(qmake_cargo_hello_init)
