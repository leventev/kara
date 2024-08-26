const sbi = @import("sbi.zig");
const mm = @import("mm.zig");
const kio = @import("../../kio.zig");
const trap = @import("trap.zig");
const timer = @import("timer.zig");

pub const VirtualAddress = mm.Sv39VirtualAddress;
pub const PhysicalAddress = mm.Sv39PhysicalAddress;

pub const enableInterrupts = trap.enableInterrupts;
pub const disableInterrupts = trap.disableInterrupts;
pub const initInterrupts = trap.init;

pub const clockSource = timer.riscvClockSource;

pub fn init() linksection(".init") void {
    kio.info("Starting kara(riscv64)...", .{});
    const sbiVersion = sbi.getSpecificationVersion();
    const sbiVersionMajor = sbiVersion >> 24;
    const sbiVersionMinor = sbiVersion & 0x00FFFFFF;
    const sbiImplementationID = sbi.getImplementationID();
    const sbiImplementation: []const u8 = if (sbiImplementationID < sbi.SBIImplementations.len)
        sbi.SBIImplementations[sbiImplementationID]
    else
        "Unknown";
    const sbiImplementationVersion = sbi.getImplementationVersion();

    kio.info("SBI specification version: {}.{}", .{ sbiVersionMajor, sbiVersionMinor });
    kio.info("SBI implementation: {s} (ID={x}) version: 0x{x}", .{ sbiImplementation, sbiImplementationID, sbiImplementationVersion });

    mm.setupPaging();
}
