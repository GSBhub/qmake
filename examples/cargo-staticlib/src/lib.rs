//! Example Cargo staticlib linked into QEMU by qmake (`LANG CARGO`).
//!
//! Exposes a C ABI that the C glue (`hello_glue.c`) calls from QEMU's init.

use std::ffi::{c_char, CStr};

/// Returns a value the C glue prints, proving Rust code runs inside QEMU.
#[no_mangle]
pub extern "C" fn qmake_cargo_answer() -> u32 {
    // Use std so the link has to resolve Rust's runtime, not just a leaf fn.
    let v: Vec<u32> = (1..=6).collect();
    v.iter().sum::<u32>() * 2
}

/// Copies a NUL-terminated greeting into `buf` (C string out-param).
///
/// # Safety
/// `buf` must point to at least `len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn qmake_cargo_greeting(buf: *mut c_char, len: usize) {
    let msg = c"hello from cargo";
    let bytes = CStr::to_bytes_with_nul(msg);
    let n = bytes.len().min(len);
    if n == 0 {
        return;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr().cast(), buf, n);
    *buf.add(n - 1) = 0;
}
