const riscv64 = @import("riscv64/riscv64.zig");

const Arch = enum {
    riscv64,
};

const target = Arch.riscv64;

pub const init = switch (target) {
    Arch.riscv64 => riscv64.init,
};

pub const initInterrupts = switch (target) {
    Arch.riscv64 => riscv64.initInterrupts,
};

pub const enableInterrupts = switch (target) {
    Arch.riscv64 => riscv64.enableInterrupts,
};

pub const disableInterrupts = switch (target) {
    Arch.riscv64 => riscv64.disableInterrupts,
};

pub const VirtualAddress = switch (target) {
    Arch.riscv64 => riscv64.VirtualAddress,
};

pub const PhysicalAddress = switch (target) {
    Arch.riscv64 => riscv64.PhysicalAddress,
};

// TODO: better way to abstract interrupts
pub const clockSource = switch (target) {
    Arch.riscv64 => riscv64.clockSource,
};
