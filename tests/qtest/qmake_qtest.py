#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
qmake out-of-tree qtest functional harness.

Goes beyond "the device is registered in QEMU": it boots qemu-system-aarch64
under the *qtest* accelerator and drives raw guest-physical MMIO against the
out-of-tree example devices, proving each one reaches realize() *and* services
its MemoryRegionOps read/write handlers.

It reuses QEMU's own shipped qtest client (extern/qemu/python/qemu/machine), so
there is nothing to compile or link -- it is pure stdlib + that package.

Under -accel qtest the guest CPU never executes, so no firmware enumerates PCI.
The harness therefore performs minimal PCI bring-up itself through the ARM
'virt' board's ECAM window before touching a device BAR:

    ECAM (config) base      : 0x3f000000   (hw/arm/virt.c [VIRT_PCIE_ECAM])
    32-bit MMIO window base : 0x10000000   (hw/arm/virt.c [VIRT_PCIE_MMIO])

Note: the Rust SysBus example devices (qmake-hello-rs, qmake-new-edu-rs) are not
mapped to any fixed address by the virt board, so they have no guest-physical
MMIO window to poke here; they stay covered by the LOAD-level qom-list-types
check in CI.

Usage:
    qmake_qtest.py [QEMU_BINARY]

QEMU_BINARY defaults to build/qemu-build/qemu-system-aarch64 (or the
QMAKE_QEMU_BINARY env var).
"""

import os
import sys

# --- locate the repo + QEMU's python package (no install required) ------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO_ROOT, "extern", "qemu", "python"))

from qemu.machine.qtest import QEMUQtestMachine  # noqa: E402

# --- virt board PCIe layout ---------------------------------------------------

ECAM_BASE = 0x3F000000      # config space (one 4 KiB window per devfn)
MMIO_BASE = 0x10000000      # 32-bit non-prefetchable MMIO window

# PCI config register offsets / bits
PCI_CFG_ID = 0x00           # vendor (low 16) | device (high 16)
PCI_CFG_COMMAND = 0x04
PCI_CFG_BAR0 = 0x10
PCI_COMMAND_MEMORY = 0x0002  # respond to memory-space accesses

PCI_VENDOR_ID_QEMU = 0x1234


class QTestError(Exception):
    pass


# --- thin wrappers over the qtest text protocol -------------------------------

def _expect_ok(resp, what):
    parts = resp.split()
    if not parts or parts[0] != "OK":
        raise QTestError(f"{what}: unexpected qtest response {resp!r}")
    return parts


def readl(vm, addr):
    parts = _expect_ok(vm.qtest(f"readl 0x{addr:x}"), f"readl 0x{addr:x}")
    return int(parts[1], 0) & 0xFFFFFFFF


def writel(vm, addr, value):
    _expect_ok(vm.qtest(f"writel 0x{addr:x} 0x{value & 0xFFFFFFFF:x}"),
               f"writel 0x{addr:x}")


# --- minimal PCI bring-up over ECAM -------------------------------------------

def _cfg_addr(slot, offset):
    # bus 0, function 0: ECAM offset is devfn << 12, devfn = slot << 3
    return ECAM_BASE + (slot << 3 << 12) + offset


def find_pci_device(vm, vendor_id, device_id):
    """Scan bus 0 for a (vendor, device) match; return its slot number."""
    want = (vendor_id & 0xFFFF) | ((device_id & 0xFFFF) << 16)
    for slot in range(32):
        ident = readl(vm, _cfg_addr(slot, PCI_CFG_ID))
        if ident == want:
            return slot
    raise QTestError(
        f"device {vendor_id:#06x}:{device_id:#06x} not found on PCIe bus 0")


def map_bar0(vm, slot, base=MMIO_BASE):
    """Size + assign BAR0, enable memory decode, return the BAR base address."""
    # Size the BAR: all-ones probe, then decode the writable address bits.
    writel(vm, _cfg_addr(slot, PCI_CFG_BAR0), 0xFFFFFFFF)
    probe = readl(vm, _cfg_addr(slot, PCI_CFG_BAR0))
    size = (~(probe & 0xFFFFFFF0) & 0xFFFFFFFF) + 1
    if size == 0 or base % size != 0:
        raise QTestError(f"BAR0 size {size:#x} not aligned to base {base:#x}")
    # Assign and enable.
    writel(vm, _cfg_addr(slot, PCI_CFG_BAR0), base)
    cmd = readl(vm, _cfg_addr(slot, PCI_CFG_COMMAND)) & 0xFFFF
    writel(vm, _cfg_addr(slot, PCI_CFG_COMMAND), cmd | PCI_COMMAND_MEMORY)
    return base


# --- machine helper -----------------------------------------------------------

def launch(qemu_bin, driver, dev_id):
    vm = QEMUQtestMachine(
        qemu_bin,
        # highmem-ecam=off keeps PCIe config space at the low ECAM window
        # (0x3f000000); aarch64 virt otherwise relocates it to a runtime-
        # computed high address we'd have to discover.
        args=["-nodefaults", "-machine", "virt,highmem-ecam=off",
              "-cpu", "cortex-a57", "-device", f"{driver},id={dev_id}"],
    )
    vm.launch()
    return vm


# --- test cases ---------------------------------------------------------------

def test_qmake_hello_mmio_roundtrip(qemu_bin):
    """Write then read BAR0; proves realize ran and read/write handlers fire."""
    vm = launch(qemu_bin, "qmake-hello", "hello0")
    try:
        slot = find_pci_device(vm, PCI_VENDOR_ID_QEMU, 0x11E9)
        bar = map_bar0(vm, slot)
        writel(vm, bar + 0x00, 0xDEADBEEF)
        got = readl(vm, bar + 0x00)
        if got != 0xDEADBEEF:
            raise QTestError(f"MMIO round-trip: wrote 0xdeadbeef, read {got:#x}")
    finally:
        vm.shutdown()


def test_qmake_hello_realized_qmp(qemu_bin):
    """Belt-and-suspenders: assert the QOM 'realized' property is true."""
    vm = launch(qemu_bin, "qmake-hello", "hello0")
    try:
        realized = vm.cmd("qom-get", path="/machine/peripheral/hello0",
                          property="realized")
        if realized is not True:
            raise QTestError(f"qom-get realized returned {realized!r}")
    finally:
        vm.shutdown()


def test_new_edu_register_semantics(qemu_bin):
    """Exercise value-transforming registers, not just a scratch cell."""
    vm = launch(qemu_bin, "new_edu", "edu0")
    try:
        slot = find_pci_device(vm, PCI_VENDOR_ID_QEMU, 0x11EA)
        bar = map_bar0(vm, slot)
        # 0x00: read-only magic identification register.
        ident = readl(vm, bar + 0x00)
        if ident != 0x010000ED:
            raise QTestError(f"new_edu ID reg: expected 0x010000ed, got {ident:#x}")
        # 0x04: device stores the bitwise inverse of what is written.
        writel(vm, bar + 0x04, 0x12345678)
        inv = readl(vm, bar + 0x04)
        if inv != (~0x12345678 & 0xFFFFFFFF):
            raise QTestError(f"new_edu inv reg: expected 0xedcba987, got {inv:#x}")
    finally:
        vm.shutdown()


TESTS = [
    test_qmake_hello_mmio_roundtrip,
    test_qmake_hello_realized_qmp,
    test_new_edu_register_semantics,
]


def main(argv):
    qemu_bin = (argv[1] if len(argv) > 1
                else os.environ.get("QMAKE_QEMU_BINARY")
                or os.path.join(REPO_ROOT, "build", "qemu-build",
                                "qemu-system-aarch64"))
    if not os.path.exists(qemu_bin):
        print(f"qtest: QEMU binary not found: {qemu_bin}", file=sys.stderr)
        return 2

    failures = 0
    for test in TESTS:
        try:
            test(qemu_bin)
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001 - report and keep going
            failures += 1
            print(f"FAIL {test.__name__}: {exc}")

    print(f"\nqtest: {len(TESTS) - failures}/{len(TESTS)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
