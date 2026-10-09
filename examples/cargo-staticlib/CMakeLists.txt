# Example LANG CARGO module: a cargo-built Rust staticlib (any dependencies
# allowed) plus C glue, statically linked into every QEMU target.
#   QMAKE_CARGO_HELLO=1 build/qemu-build/qemu-system-<arch> -M none -S -display none
include(QmakeAddModule)

qmake_add_qemu_module(
  NAME     cargo_hello
  LANG     CARGO
  MANIFEST Cargo.toml
  CRATE    qmake_cargo_hello
  SOURCES  hello_glue.c)
