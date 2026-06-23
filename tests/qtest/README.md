# Writing out-of-tree qtest functional tests

This guide shows how to add a functional test that proves a qmake-built
out-of-tree QEMU device actually *works* — that it reaches `realize()` and
services its MMIO read/write handlers — rather than only confirming it is
registered (which the `-device help` / `qom-list-types` checks already cover).

Tests live in [`qmake_qtest.py`](qmake_qtest.py). Start by reading it; this guide
explains the moving parts so you can add a case for your own device.

## How it works

QEMU ships a `qtest` accelerator: a back-door that lets a test process issue raw
guest-physical memory accesses against a running VM. Under `-accel qtest` the
guest CPU never executes, so there is no firmware and no guest OS — just the
hardware model, frozen at the point right after machine init (so your device's
`realize()` has already run).

We drive it from Python using QEMU's own shipped client,
`extern/qemu/python/qemu/machine/qtest.py` (`QEMUQtestMachine`). Nothing is
compiled or linked — the harness is pure stdlib plus that package, which
`qmake_qtest.py` puts on `sys.path` automatically.

The qtest wire protocol is line-based; the helpers in `qmake_qtest.py` wrap it:

| Helper | qtest command | Meaning |
| --- | --- | --- |
| `readl(vm, addr)` | `readl 0x<addr>` | read 32 bits at a guest-physical address |
| `writel(vm, addr, val)` | `writel 0x<addr> 0x<val>` | write 32 bits |

(`readb/w/q` and `writeb/w/q` exist in the protocol too; add wrappers if you need
other widths.)

## The catch: nothing sets up your device's address

Because no firmware runs, a **PCI device's BAR is unprogrammed** and PCI memory
decoding is disabled. The test must do minimal PCI bring-up itself before it can
touch the device. `qmake_qtest.py` provides two helpers for this on the ARM
`virt` board:

- `find_pci_device(vm, vendor_id, device_id)` — scans bus 0's ECAM config space
  and returns the slot where your `(vendor, device)` pair lives.
- `map_bar0(vm, slot, base=MMIO_BASE)` — sizes BAR0, assigns it `base`
  (`0x10000000`, the virt 32-bit MMIO window), enables `PCI_COMMAND_MEMORY`, and
  returns the BAR's guest-physical base. After this, `readl/writel` at
  `base + offset` hit your device's `MemoryRegionOps`.

### virt board gotcha: low vs high ECAM

aarch64 `virt` defaults to relocating PCIe config space (ECAM) to a
runtime-computed high address, so reads at the documented low window
(`0x3f000000`) return zero. The harness launches with
`-machine virt,highmem-ecam=off` to pin ECAM to the low window so config
addresses are deterministic. Keep that flag if you copy the launch helper.

## Adding a test for a PCI device

If your device is a `PCIDevice` (like `qmake-hello` / `new_edu`), a test is a few
lines. Pattern, modeled on `test_qmake_hello_mmio_roundtrip`:

```python
def test_my_device(qemu_bin):
    vm = launch(qemu_bin, "my-device", "mydev0")   # -device my-device,id=mydev0
    try:
        slot = find_pci_device(vm, PCI_VENDOR_ID_QEMU, 0xABCD)  # your device_id
        bar = map_bar0(vm, slot)

        writel(vm, bar + 0x00, 0xcafef00d)
        got = readl(vm, bar + 0x00)
        if got != 0xcafef00d:
            raise QTestError(f"round-trip: wrote 0xcafef00d, read {got:#x}")
    finally:
        vm.shutdown()
```

Then append the function to the `TESTS` list at the bottom of the file. That's it
— the runner executes every entry and reports `PASS`/`FAIL`.

Things to get right:

- **vendor/device id** must match your device's `class_init`
  (`k->vendor_id` / `k->device_id`). `find_pci_device` asserts the match, so a
  wrong id fails loudly rather than testing the wrong device.
- **assert real behavior, not a scratch cell.** A dead/unmapped BAR reads back
  `0xffffffff`, so any assertion against a specific value already distinguishes a
  working handler from a broken one. Prefer value-transforming registers where
  you can — e.g. `new_edu`'s read-only magic ID (`0x010000ed` at `0x00`) and its
  bitwise-inverse register (write `x`, read `~x` at `0x04`) — they can only pass
  if the read/write callbacks actually ran.
- **always `shutdown()` in `finally`**, so a failed assertion doesn't leak a QEMU
  process.

## Verifying realize directly (optional)

MMIO working already implies `realize()` ran (the BAR is registered there). If you
want an explicit, belt-and-suspenders check, query the QOM property over QMP —
see `test_qmake_hello_realized_qmp`:

```python
realized = vm.cmd("qom-get", path="/machine/peripheral/mydev0",
                  property="realized")
assert realized is True
```

The `id=` you pass to `launch()` becomes the `/machine/peripheral/<id>` path.

## SysBus and other non-PCI devices

The PCI helpers assume a BAR. A `SysBusDevice` (like the Rust `qmake-hello-rs`)
realizes but is **not mapped to any address** unless a board calls
`sysbus_mmio_map`, so there is no guest-physical window to poke under a stock
`virt` machine. Options:

- Wrap the device behind a small PCI shim, or
- Use a machine/board that maps it at a known address, then `readl/writel` there
  directly (no ECAM/BAR dance needed — skip `find_pci_device`/`map_bar0`).

Until then, such devices stay covered by the registration-level
`qom-list-types` check in CI.

## Running

```sh
# Build QEMU with the examples linked in (once):
cmake -S . -B build -DQMAKE_BUILD_EXAMPLES=ON
cmake --build build

# Directly:
python3 tests/qtest/qmake_qtest.py build/qemu-build/qemu-system-aarch64

# Or via ctest (registered when QMAKE_BUILD_EXAMPLES=ON):
ctest --test-dir build -R qtest-mmio --output-on-failure
```

The binary path can also come from the `QMAKE_QEMU_BINARY` env var, or defaults to
`build/qemu-build/qemu-system-aarch64`. CI runs the same harness as a FUNCTION
step in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).
