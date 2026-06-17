//! `qmake-new-edu-rs`: a SysBus rendering of QEMU's `edu` educational device.
//!
//! Rust analog of the C `new_edu` example. QEMU 10.2's Rust API has no PCI/MSI/DMA
//! bindings, so this keeps `edu`'s signature *educational* feature — the register
//! map with a synchronous factorial computation — on a `SysBusDevice` instead of a
//! PCI device. The threaded/IRQ/DMA machinery of the C `edu` is intentionally
//! omitted (no Rust bindings yet).
//!
//! Register map (all 32-bit):
//!   0x00  identification (read-only magic)
//!   0x04  bitwise-inverse register (write stores ~value, read returns it)
//!   0x08  factorial (write sets operand and computes synchronously; read result)
//!   0x20  status / scratch

use std::ffi::CStr;

use bql::BqlCell;
use common::uninit_field_mut;
use hwcore::{
    DeviceImpl, DeviceState, ResettablePhasesImpl, SysBusDevice, SysBusDeviceImpl,
    SysBusDeviceMethods,
};
use qom::{prelude::*, ObjectImpl, ParentField, ParentInit};
use system::{hwaddr, MemoryRegion, MemoryRegionOps, MemoryRegionOpsBuilder};
use util::{log::Log, log_mask_ln};

pub const TYPE_QMAKE_NEW_EDU_RS: &CStr = c"qmake-new-edu-rs";

const REG_ID: hwaddr = 0x00;
const REG_INV: hwaddr = 0x04;
const REG_FACT: hwaddr = 0x08;
const REG_STATUS: hwaddr = 0x20;

/// Identification magic, mirroring the C `edu`'s `0x010000edu` version word.
const EDU_IDENT: u64 = 0x0100_00ed;

#[repr(C)]
#[derive(qom::Object, hwcore::Device)]
pub struct QmakeNewEduState {
    parent_obj: ParentField<SysBusDevice>,
    iomem: MemoryRegion,
    inv: BqlCell<u32>,
    fact: BqlCell<u32>,
    status: BqlCell<u32>,
}

unsafe impl ObjectType for QmakeNewEduState {
    type Class = <SysBusDevice as ObjectType>::Class;
    const TYPE_NAME: &'static CStr = TYPE_QMAKE_NEW_EDU_RS;
}

// Declare the QOM ancestry so IsA<..>-bounded methods (e.g. init_mmio) apply.
qom_isa!(QmakeNewEduState: SysBusDevice, DeviceState, Object);

impl ObjectImpl for QmakeNewEduState {
    type ParentType = SysBusDevice;

    const INSTANCE_INIT: Option<unsafe fn(ParentInit<Self>)> = Some(Self::init);
    const INSTANCE_POST_INIT: Option<fn(&Self)> = Some(Self::post_init);
    const CLASS_INIT: fn(&mut Self::Class) = Self::Class::class_init::<Self>;
}

impl QmakeNewEduState {
    const MMIO_SIZE: u64 = 0x1000;

    /// # Safety
    /// See [`super::hello::QmakeHelloState::init`].
    unsafe fn init(mut this: ParentInit<Self>) {
        static OPS: MemoryRegionOps<QmakeNewEduState> =
            MemoryRegionOpsBuilder::<QmakeNewEduState>::new()
                .read(&QmakeNewEduState::read)
                .write(&QmakeNewEduState::write)
                .native_endian()
                .impl_sizes(4, 4)
                .build();

        MemoryRegion::init_io(
            &mut uninit_field_mut!(*this, iomem),
            &OPS,
            "qmake-new-edu-rs",
            Self::MMIO_SIZE,
        );
        uninit_field_mut!(*this, inv).write(BqlCell::new(0));
        uninit_field_mut!(*this, fact).write(BqlCell::new(0));
        uninit_field_mut!(*this, status).write(BqlCell::new(0));
    }

    fn post_init(&self) {
        self.init_mmio(&self.iomem);
    }

    fn read(&self, offset: hwaddr, _size: u32) -> u64 {
        match offset {
            REG_ID => EDU_IDENT,
            REG_INV => u64::from(self.inv.get()),
            REG_FACT => u64::from(self.fact.get()),
            REG_STATUS => u64::from(self.status.get()),
            _ => {
                log_mask_ln!(Log::GuestError, "qmake-new-edu-rs: bad read offset {offset}");
                0
            }
        }
    }

    fn write(&self, offset: hwaddr, value: u64, _size: u32) {
        let value = value as u32;
        match offset {
            REG_INV => self.inv.set(!value),
            REG_FACT => {
                // Synchronous factorial, like edu's worker thread but inline.
                let mut n = value;
                let mut result: u32 = 1;
                while n > 0 {
                    result = result.wrapping_mul(n);
                    n -= 1;
                }
                self.fact.set(result);
            }
            REG_STATUS => self.status.set(value),
            _ => log_mask_ln!(Log::GuestError, "qmake-new-edu-rs: bad write offset {offset}"),
        }
    }

    fn realize(&self) -> util::Result<()> {
        log_mask_ln!(
            Log::Unimp,
            "qmake-new-edu-rs: realized (out-of-tree Rust edu-style SysBus device)"
        );
        Ok(())
    }
}

impl DeviceImpl for QmakeNewEduState {
    const REALIZE: Option<fn(&Self) -> util::Result<()>> = Some(Self::realize);
}

impl ResettablePhasesImpl for QmakeNewEduState {}
impl SysBusDeviceImpl for QmakeNewEduState {}
