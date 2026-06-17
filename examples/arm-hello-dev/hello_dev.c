/*
 * qmake example: a minimal out-of-tree QEMU peripheral.
 *
 * Demonstrates a self-contained, user-creatable QOM device built entirely out of
 * tree and statically linked into QEMU by the qmake harness. It is a tiny PCI
 * device (so it is pluggable via -device on any machine with a PCI/PCIe bus, e.g.
 * the ARM 'virt' board) that exposes a small MMIO BAR and logs on realize and on
 * register access -- enough to prove the device was compiled in, registered with
 * QOM, and is instantiable.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "qemu/osdep.h"
#include "qemu/log.h"
#include "hw/pci/pci.h"
#include "hw/pci/pci_device.h"
#include "qom/object.h"

#define TYPE_QMAKE_HELLO "qmake-hello"
OBJECT_DECLARE_SIMPLE_TYPE(QmakeHelloState, QMAKE_HELLO)

struct QmakeHelloState {
    PCIDevice parent_obj;

    MemoryRegion mmio;
    uint32_t reg;
};

#define QMAKE_HELLO_MMIO_SIZE 0x1000

static uint64_t qmake_hello_read(void *opaque, hwaddr offset, unsigned size)
{
    QmakeHelloState *s = QMAKE_HELLO(opaque);

    qemu_log("qmake-hello: read  offset=0x%" HWADDR_PRIx " size=%u -> 0x%x\n",
             offset, size, s->reg);
    return s->reg;
}

static void qmake_hello_write(void *opaque, hwaddr offset, uint64_t value,
                              unsigned size)
{
    QmakeHelloState *s = QMAKE_HELLO(opaque);

    qemu_log("qmake-hello: write offset=0x%" HWADDR_PRIx " size=%u value=0x%"
             PRIx64 "\n", offset, size, value);
    s->reg = (uint32_t)value;
}

static const MemoryRegionOps qmake_hello_ops = {
    .read = qmake_hello_read,
    .write = qmake_hello_write,
    .endianness = DEVICE_NATIVE_ENDIAN,
};

static void qmake_hello_realize(PCIDevice *pdev, Error **errp)
{
    QmakeHelloState *s = QMAKE_HELLO(pdev);

    memory_region_init_io(&s->mmio, OBJECT(s), &qmake_hello_ops, s,
                          TYPE_QMAKE_HELLO, QMAKE_HELLO_MMIO_SIZE);
    pci_register_bar(pdev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->mmio);

    qemu_log("qmake-hello: realized (out-of-tree PCI device built by qmake)\n");
}

static void qmake_hello_class_init(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->realize = qmake_hello_realize;
    k->vendor_id = PCI_VENDOR_ID_QEMU;
    k->device_id = 0x11e9;
    k->revision = 0x10;
    k->class_id = PCI_CLASS_OTHERS;

    dc->desc = "qmake example out-of-tree peripheral";
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo qmake_hello_info = {
    .name = TYPE_QMAKE_HELLO,
    .parent = TYPE_PCI_DEVICE,
    .instance_size = sizeof(QmakeHelloState),
    .class_init = qmake_hello_class_init,
    .interfaces = (InterfaceInfo[]) {
        { INTERFACE_CONVENTIONAL_PCI_DEVICE },
        { },
    },
};

static void qmake_hello_register_types(void)
{
    type_register_static(&qmake_hello_info);
}

type_init(qmake_hello_register_types)
