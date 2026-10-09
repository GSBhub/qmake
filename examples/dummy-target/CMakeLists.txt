# Example out-of-tree QEMU *target*: a do-nothing CPU ("qmdummy") whose
# translator turns every instruction into a halt that prints the PC and shuts
# QEMU down. Exercises qmake_add_qemu_target end to end:
#   build/qemu-build/qemu-system-qmdummy -M none -cpu qmdummy -m 1M -nographic
include(QmakeInjectTarget)

qmake_add_qemu_target(
  NAME      qmdummy
  SRCDIR    cpu
  LONG_BITS 32)
