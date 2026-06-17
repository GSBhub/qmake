# Example: out-of-tree QEMU peripherals written in Rust, statically linked into
# QEMU by qmake. Declaring a LANG RUST module auto-enables --enable-rust on the
# QEMU build. QEMU 10.2's Rust API supports SysBusDevice (no PCI yet), so these
# are SysBus devices. Build with -DQMAKE_BUILD_EXAMPLES=ON.
include(QmakeAddModule)

qmake_add_qemu_module(
  NAME    rust_devices
  LANG    RUST
  CRATE   qmake_rust_devices
  SOURCES src/lib.rs src/hello.rs src/new_edu.rs
  TARGETS arm)
