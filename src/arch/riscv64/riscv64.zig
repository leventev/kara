const sbi = @import("sbi.zig");
const mm = @import("mm.zig");
const kio = @import("../../kio.zig");
const trap = @import("trap.zig");

pub const VirtualAddress = mm.Sv39VirtualAddress;
pub const PhysicalAddress = mm.Sv39PhysicalAddress;

pub const enableInterrupts = trap.enableInterrupts;
pub const disableInterrupts = trap.disableInterrupts;
pub const initInterrupts = trap.init;

pub fn init() linksection(".init") void {
    kio.log("Starting kara(riscv64)...", .{});
    const sbiVersion = sbi.getSpecificationVersion();
    const sbiVersionMajor = sbiVersion >> 24;
    const sbiVersionMinor = sbiVersion & 0x00FFFFFF;
    const sbiImplementationID = sbi.getImplementationID();
    const sbiImplementation: []const u8 = if (sbiImplementationID < sbi.SBIImplementations.len)
        sbi.SBIImplementations[sbiImplementationID]
    else
        "Unknown";
    const sbiImplementationVersion = sbi.getImplementationVersion();

    kio.log("SBI specification version: {}.{}", .{ sbiVersionMajor, sbiVersionMinor });
    kio.log("SBI implementation: {s} (ID={x}) version: 0x{x}", .{ sbiImplementation, sbiImplementationID, sbiImplementationVersion });

    mm.setupPaging();
}
