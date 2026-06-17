//! Example out-of-tree QEMU peripherals written in Rust, built by qmake.
//!
//! These are idiomatic QOM `SysBusDevice` implementations modeled on QEMU's
//! in-tree Rust devices (`rust/hw/char/pl011`, `rust/hw/timer/hpet`). They are
//! the Rust analogs of the C examples:
//!
//! * [`hello`] — `qmake-hello-rs`, a minimal MMIO register device.
//! * [`new_edu`] — `qmake-new-edu-rs`, a SysBus rendering of QEMU's `edu`
//!   educational device (id / xor / synchronous-factorial register map).
//!
//! QEMU 10.2's Rust API exposes `SysBusDevice` (PCI/MSI/DMA have no Rust bindings
//! yet), so these are SysBus devices rather than PCI like the C examples.
//!
//! Building: the dependency crates generate their FFI via meson's `rust.bindgen`,
//! so a standalone `cargo build` needs `MESON_BUILD_ROOT` pointing at a configured
//! QEMU build (one built with Rust enabled). See the repo README.

mod hello;
mod new_edu;

pub use hello::TYPE_QMAKE_HELLO_RS;
pub use new_edu::TYPE_QMAKE_NEW_EDU_RS;
