//! `qmake-hello-rs`: a minimal out-of-tree Rust SysBus peripheral.
//!
//! Rust analog of the C `hello_dev` example: a single 32-bit MMIO register that
//! logs on realize. Modeled on QEMU's in-tree `rust/hw/timer/hpet` skeleton.

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

pub const TYPE_QMAKE_HELLO_RS: &CStr = c"qmake-hello-rs";

#[repr(C)]
#[derive(qom::Object, hwcore::Device)]
/// A trivial SysBus device exposing one read/write 32-bit register.
pub struct QmakeHelloState {
    parent_obj: ParentField<SysBusDevice>,
    iomem: MemoryRegion,
    reg: BqlCell<u32>,
}

// No custom class is needed (cf. OBJECT_DECLARE_SIMPLE_TYPE in C); reuse the
// SysBusDevice class directly.
unsafe impl ObjectType for QmakeHelloState {
    type Class = <SysBusDevice as ObjectType>::Class;
    const TYPE_NAME: &'static CStr = TYPE_QMAKE_HELLO_RS;
}

// Declare the QOM ancestry so IsA<..>-bounded methods (e.g. init_mmio) apply.
qom_isa!(QmakeHelloState: SysBusDevice, DeviceState, Object);

impl ObjectImpl for QmakeHelloState {
    type ParentType = SysBusDevice;

    const INSTANCE_INIT: Option<unsafe fn(ParentInit<Self>)> = Some(Self::init);
    const INSTANCE_POST_INIT: Option<fn(&Self)> = Some(Self::post_init);
    const CLASS_INIT: fn(&mut Self::Class) = Self::Class::class_init::<Self>;
}

impl QmakeHelloState {
    const MMIO_SIZE: u64 = 0x1000;

    /// # Safety
    /// `this` must point to a correctly sized/aligned `QmakeHelloState` whose
    /// fields (except `parent_obj`) are uninitialized; called at most once.
    unsafe fn init(mut this: ParentInit<Self>) {
        static OPS: MemoryRegionOps<QmakeHelloState> =
            MemoryRegionOpsBuilder::<QmakeHelloState>::new()
                .read(&QmakeHelloState::read)
                .write(&QmakeHelloState::write)
                .native_endian()
                .impl_sizes(4, 4)
                .build();

        MemoryRegion::init_io(
            &mut uninit_field_mut!(*this, iomem),
            &OPS,
            "qmake-hello-rs",
            Self::MMIO_SIZE,
        );
        uninit_field_mut!(*this, reg).write(BqlCell::new(0));
    }

    fn post_init(&self) {
        self.init_mmio(&self.iomem);
    }

    fn read(&self, _offset: hwaddr, _size: u32) -> u64 {
        u64::from(self.reg.get())
    }

    fn write(&self, _offset: hwaddr, value: u64, _size: u32) {
        self.reg.set(value as u32);
    }

    fn realize(&self) -> util::Result<()> {
        log_mask_ln!(
            Log::Unimp,
            "qmake-hello-rs: realized (out-of-tree Rust SysBus device built by qmake)"
        );
        Ok(())
    }
}

impl DeviceImpl for QmakeHelloState {
    const REALIZE: Option<fn(&Self) -> util::Result<()>> = Some(Self::realize);
}

impl ResettablePhasesImpl for QmakeHelloState {}
impl SysBusDeviceImpl for QmakeHelloState {}
