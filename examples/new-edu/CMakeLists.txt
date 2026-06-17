# Example: QEMU's "edu" educational PCI device, copied out of tree and renamed
# to "new_edu", statically linked into QEMU by qmake. Shows that a real,
# non-trivial upstream device (MSI, DMA, worker thread, timers) builds and links
# unmodified through the harness. Build with -DQMAKE_BUILD_EXAMPLES=ON.
include(QmakeAddModule)

qmake_add_qemu_module(
  NAME     new_edu
  LANG     C
  SOURCES  new_edu.c
  TARGETS  arm           # built into the arm/aarch64 targets we configure
  LINKAGE  STATIC)
