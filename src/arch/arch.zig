const riscv64 = @import("riscv64/riscv64.zig");

const Arch = enum {
    riscv64,
};

const target = Arch.riscv64;

pub const init = switch (target) {
    Arch.riscv64 => riscv64.init,
};

pub const VirtualAddress = switch (target) {
    Arch.riscv64 => riscv64.VirtualAddress,
};

pub const PhysicalAddress = switch (target) {
    Arch.riscv64 => riscv64.PhysicalAddress,
};
