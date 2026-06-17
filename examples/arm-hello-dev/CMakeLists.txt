# Example out-of-tree QEMU peripheral: an ARM-only QOM device statically linked
# into QEMU by qmake. Build with -DQMAKE_BUILD_EXAMPLES=ON.
include(QmakeAddModule)

qmake_add_qemu_module(
  NAME     hello_dev
  LANG     C
  SOURCES  hello_dev.c
  TARGETS  arm           # ARM-only: gated on CONFIG QMAKE_HELLO_DEV (default y if ARM)
  LINKAGE  STATIC
  FEATURES qom log)
