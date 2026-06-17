//! Template for an out-of-tree QEMU peripheral written in Rust.
//!
//! v1 status: scaffold only. The qmake C path (static injection into QEMU's
//! meson build) is fully wired; the Rust path reuses QEMU's in-tree Rust crates
//! (`qom`, `bql`, `system`, ... under `extern/qemu/rust`) whose FFI bindings are
//! produced by meson's `rust.bindgen`. A real Rust device is therefore built and
//! linked through the same meson injection as C (`rust.static_library`), which is
//! staged for a later milestone.
//!
//! When that lands, a device here looks structurally like QEMU's in-tree
//! `rust/hw/char/pl011`: define a `#[repr(C)]` state struct, implement the QOM
//! `ObjectImpl`/`DeviceImpl` traits from the `qom`/`system` crates, and register
//! the type via a constructor.

/// Placeholder marker so the crate builds standalone in v1 (no QEMU deps yet).
/// Replace with real QOM type registration once the Rust meson injection lands.
#[no_mangle]
pub extern "C" fn qmake_template_marker() -> u32 {
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn marker_is_zero() {
        assert_eq!(super::qmake_template_marker(), 0);
    }
}
