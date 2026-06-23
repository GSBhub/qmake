# qmake — out-of-tree QEMU module build system

`qmake` is a CMake harness for writing QEMU peripherals/devices **out of tree** (in
C or Rust) and integrating them with a chosen QEMU *without forking it*. You point it
at a QEMU source tree, declare your modules, and it builds a QEMU with your devices
statically linked in — with correct per-target (e.g. ARM-only) gating handled by
QEMU's own Kconfig.

It is meant to be consumed as a CMake project you `add_subdirectory()` into an
external project (see the sibling [`avatar-cm`](../avatar-cm) for a full consumer),
and as a Cargo workspace for Rust peripherals.

## Status (v1)

| Capability | State |
|---|---|
| Build a configurable QEMU via `ExternalProject` | ✅ |
| `qmake::osdep / qapi / log / qom / target-<arch>` feature modules (meson introspection) | ✅ |
| Static link a C device into QEMU (meson + Kconfig injection) | ✅ |
| Per-target / ARM-only gating | ✅ |
| Per-target (`specific_ss`) modules touching CPU internals (`SCOPE TARGET`) | ✅ |
| Pull in in-tree QEMU devices a module needs (`SELECTS`) | ✅ |
| Rust devices linked into QEMU (reuse QEMU's in-tree Rust crates) | ✅ |
| LD_PRELOAD / `--enable-modules` load paths | 🚧 API present, not built |
| `libqemu-afl-bridge` / avatar-qemu targets | 🚧 supported via `QMAKE_QEMU_DIR`, not yet validated |

## Requirements

The host needs QEMU's build prerequisites: `meson`, `ninja`, a C compiler, `python3`,
`pkg-config`, `flex`, `bison`, and the `glib-2.0` / `pixman-1` dev packages. CMake ≥ 3.30.

## Quick start

```sh
# 1. Clone with the QEMU submodule (default: upstream QEMU pinned to v10.2.3)
git clone <this-repo> qmake && cd qmake
git submodule update --init --depth 1 extern/qemu

# 2. Configure + build (builds QEMU with the bundled ARM-only example device)
cmake -S . -B build -DQMAKE_BUILD_EXAMPLES=ON
cmake --build build

# 3. Run it — the out-of-tree device is statically linked in
build/qemu-build/qemu-system-aarch64 -device help | grep qmake-hello
build/qemu-build/qemu-system-aarch64 -M virt -device qmake-hello -nographic -S -monitor stdio
#   -> logs: "qmake-hello: realized (out-of-tree PCI device built by qmake)"
```

## Targeting a different QEMU

The QEMU tree is selected by `QMAKE_QEMU_DIR`, defaulting to the `extern/qemu`
submodule. Point it at any other local clone to target that instead — the harness
never assumes the submodule path and always builds out-of-source under your build dir:

```sh
cmake -S . -B build -DQMAKE_QEMU_DIR=/path/to/avatar-qemu
cmake -S . -B build -DQMAKE_QEMU_DIR=/path/to/libqemu-afl-bridge
```

### Options

| Variable | Default | Purpose |
|---|---|---|
| `QMAKE_QEMU_DIR` | `extern/qemu` | QEMU source tree to build against |
| `QMAKE_QEMU_TARGETS` | `aarch64-softmmu` | QEMU `--target-list` (space/comma separated) |
| `QMAKE_QEMU_CONFIGURE_ARGS` | *(empty)* | extra args appended to QEMU `configure` |
| `QMAKE_ENABLE_MODULES` | `OFF` | pass `--enable-modules` (for the future MODULE path) |
| `QMAKE_ENABLE_RUST` | `OFF` | force `--enable-rust`; otherwise auto-enabled when a `LANG RUST` module is declared |
| `QMAKE_BUILD_EXAMPLES` | `OFF` | build the bundled example devices |

The QEMU build is defined by a deferred finalizer that runs after all
`qmake_add_qemu_module(...)` calls, so declaring any `LANG RUST` module
automatically adds `--enable-rust` to QEMU's configure — no manual flag needed.

## Declaring a module

```cmake
include(QmakeAddModule)

qmake_add_qemu_module(
  NAME     my_dev
  LANG     C              # C or RUST
  SOURCES  my_dev.c
  HEADERS  my_dev.h compat.h   # symlinked beside sources so #include "..." resolves
  TARGETS  arm            # arch gating; omit for all targets
  SCOPE    SYSTEM         # SYSTEM (system_ss, default) or TARGET (specific_ss,
                          #   per-target — needed to touch target/<arch>/cpu.h)
  SELECTS  ARM_TIMER      # Kconfig select: pull these in-tree QEMU devices into the build
  LINKAGE  STATIC         # STATIC built now; PRELOAD/MODULE staged
  FEATURES qom log)       # extra qmake:: feature modules (non-static paths)
```

- **`SCOPE SYSTEM`** (default) builds into `system_ss` gated on a `CONFIG_QMAKE_<NAME>`
  Kconfig symbol (`default y [if <ARCH>]`). **`SCOPE TARGET`** builds into `specific_ss`
  gated on `TARGET_<arch>` so the sources compile per-target with `-DCOMPILING_PER_TARGET`
  and access to `target/<arch>/cpu.h` (machines, CPU-internals code).
- **`HEADERS`** are symlinked next to the (symlinked) sources in the QEMU tree so
  `#include "foo.h"` resolves; a generated `qmake_qemu_version.h` is always provided
  (with `QMAKE_QEMU_AT_LEAST(maj,min)`) for version-guarded compat shims.
- **`SELECTS`** adds Kconfig `select` lines so the named in-tree QEMU devices are
  compiled in whenever the module is (regardless of which boards the build includes).

For `LINKAGE STATIC`, qmake registers the sources into QEMU's build graph under
`hw/qmake-modules/<name>/` (generated `meson.build` + `Kconfig`) and patches
`hw/meson.build` / `hw/Kconfig` idempotently behind `# qmake-inject:` markers.
QEMU's meson then compiles and links the device, and Kconfig handles per-target
gating (`config QMAKE_<NAME>` with `default y if <ARCH>`).

## Feature modules

For code **not** compiled by QEMU's own meson (LD_PRELOAD/module/Rust/tooling/IDE),
qmake derives QEMU's compile environment from `compile_commands.json` (a meson
introspection artifact) and exposes it as INTERFACE targets:

- `qmake::osdep` — include dirs + base defines + glib; lets a TU `#include "qemu/osdep.h"`.
- `qmake::qapi` — osdep + the generated qapi header dir.
- `qmake::log`, `qmake::qom` — osdep groupings.
- `qmake::target-<arch>` — osdep + per-target includes + `-DCOMPILING_PER_TARGET` (ARM-only, …).

These become available after the first QEMU build; re-run `cmake` to populate them.

## Rust

QEMU 10.x ships its own Rust crates (`rust/qom`, `rust/bql`, `rust/system`, …) whose
FFI bindings are generated by meson's `rust.bindgen`. Out-of-tree Rust devices reuse
those crates (by path into `${QMAKE_QEMU_DIR}/rust/*`) and link through the same meson
injection as C. Declaring a `LANG RUST` module auto-enables Rust in the QEMU build.

Two host prerequisites are needed for Rust (beyond the C ones): a `bindgen` binary
(`cargo install bindgen-cli`) and `libclang` (e.g. `dnf install clang-devel`), which
QEMU's `rust.bindgen` uses to generate the C bindings.

A consumer building Rust modules needs a Cargo manifest with path-deps to QEMU's rust
crates; because those paths depend on where QEMU lives, qmake generates the manifest
from `QMAKE_QEMU_DIR` rather than requiring a hand-written one. `rust/template`
scaffolds such a crate. Note: QEMU 10.2's Rust API supports `SysBusDevice` (no PCI
yet), so Rust devices are SysBus-based.

### Example Rust devices

`examples/rust-devices/` is a worked crate with two idiomatic SysBus devices
(modeled on in-tree `pl011`/`hpet`): `qmake-hello-rs` (minimal MMIO register) and
`qmake-new-edu-rs` (a SysBus rendering of `edu`'s id/xor/factorial register map).

There are two ways to build it (both verified):

**Linked into QEMU (via qmake).** `examples/rust-devices/CMakeLists.txt` declares it with
`qmake_add_qemu_module(... LANG RUST ...)`. qmake registers the crate under
`extern/qemu/rust/hw/qmake-rust_devices/` (generated `meson.build` builds it as a
`rust_abi: 'rust'` static_library added to `rust_devices_ss` with `link_whole`, plus a
Kconfig gate), and **auto-enables `--enable-rust`**. After `cmake --build build` the types
register with QOM (`qom-list-types` / `-device qmake-hello-rs,help`). Like the in-tree Rust
`pl011`/`hpet`, they are SysBus devices and so register but aren't `-device`-pluggable on
`virt`.

**Standalone (cargo).** The dependency crates generate their FFI via meson's `rust.bindgen`,
so a standalone `cargo build` needs `MESON_BUILD_ROOT` pointing at a Rust-enabled QEMU build:

```sh
cmake -S . -B build -DQMAKE_BUILD_EXAMPLES=ON && cmake --build build   # generates bindings + links
MESON_BUILD_ROOT="$PWD/build/qemu-build" cargo build -p qmake-rust-devices
```

(Requires `cargo install bindgen-cli` and `libclang`, e.g. `dnf install clang-devel`.)

## Testing

qmake's own tests are its bundled examples: building them exercises C (PCI), C
(target-scope), and Rust (SysBus) static injection, and the resulting QEMU is
inspected to confirm the devices linked in and registered.

```sh
# Build QEMU with all bundled example devices linked in:
cmake -S . -B build -DQMAKE_BUILD_EXAMPLES=ON
cmake --build build
Q=build/qemu-build/qemu-system-aarch64

# C PCI devices are user-creatable -> appear in -device help and instantiate:
$Q -device help | grep -E 'qmake-hello|new_edu'
printf 'quit\n' | $Q -M virt -cpu cortex-a57 -device qmake-hello -S -monitor stdio
#   -> "qmake-hello: realized (out-of-tree PCI device built by qmake)"

# Rust SysBus devices register as QOM types (not user-creatable, like in-tree pl011):
printf '{"execute":"qmp_capabilities"}\n{"execute":"qom-list-types"}\n{"execute":"quit"}\n' \
  | $Q -M virt -cpu cortex-a57 -qmp stdio -S | grep -o 'qmake-[a-z-]*-rs'

# ARM-only gating: CONFIG_QMAKE_HELLO_DEV is set for aarch64, absent for x86_64:
grep QMAKE_HELLO_DEV build/qemu-build/aarch64-softmmu-config-devices.mak

# Standalone Rust crate build (needs bindgen + libclang; see Rust section):
MESON_BUILD_ROOT="$PWD/build/qemu-build" cargo build -p qmake-rust-devices
```

Beyond confirming the devices are registered, a qtest harness boots QEMU under the
`qtest` accelerator and drives real guest-physical MMIO against the out-of-tree
devices — proving they reach `realize()` *and* service their MMIO read/write
handlers (it programs a PCI BAR over the virt board's ECAM window, then exercises
`qmake-hello`'s register round-trip and `new_edu`'s magic-ID / bitwise-inverse
registers). It reuses QEMU's own shipped qtest client, so nothing extra is built:

```sh
python3 tests/qtest/qmake_qtest.py "$Q"
#   -> PASS test_qmake_hello_mmio_roundtrip / _realized_qmp / test_new_edu_register_semantics
```

(The Rust SysBus devices aren't mapped to a fixed MMIO address by the virt board, so
they stay covered by the `qom-list-types` registration check above.)

To add a qtest for your own out-of-tree device, see
[`tests/qtest/README.md`](tests/qtest/README.md).

Injection is idempotent — re-running `cmake` does not duplicate the `# qmake-inject:`
markers in `extern/qemu/hw/meson.build` / `hw/Kconfig`.

For a larger, real-world consumer with its own end-to-end test suite, see the sibling
[`avatar-cm`](../avatar-cm) project (a configurable machine built entirely via qmake).

## Cleaning the QEMU tree

Injection edits tracked QEMU files. To revert:

```sh
git -C extern/qemu checkout -- hw/meson.build hw/Kconfig
git -C extern/qemu clean -fd hw/qmake-modules
```

## Layout

```
cmake/Modules/   QmakeQemuBuild, QmakeIntrospect, QmakeFeatureModules,
                 QmakeInjectMeson, QmakeAddModule
cmake/scripts/   qmake_introspect.py  (meson introspection -> cmake vars)
extern/qemu/     QEMU submodule (configurable via QMAKE_QEMU_DIR)
examples/        arm-hello-dev (C PCI), new-edu (QEMU's edu, renamed),
                 rust-devices (idiomatic Rust SysBus devices)
rust/template/   scaffold for a Rust peripheral
Cargo.toml       workspace (rust/template, examples/rust-devices)
```
