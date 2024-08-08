const std = @import("std");
const kio = @import("kio.zig");
const dt = @import("devicetree.zig");
const mm = @import("mem/mm.zig");
const phys = @import("mem/phys.zig");
const sbi = @import("arch/riscv64/sbi.zig");

export var deviceTreePointer: *void = undefined;

const temporaryHeapSize = 65535;
var temporaryHeap: [temporaryHeapSize]u8 = undefined;

pub fn panic(msg: []const u8, errorReturnTrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    kio.log("KERNEL PANIC: {s}", .{msg});
    _ = errorReturnTrace;
    _ = ret_addr;
    while (true) {}
}

export fn kmain() void {
    kio.log("Starting kara...", .{});

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

    var fba = std.heap.FixedBufferAllocator.init(&temporaryHeap);
    const allocator = fba.allocator();

    const dtRoot = dt.readDeviceTreeBlob(allocator, deviceTreePointer) catch
        @panic("Failed to read device tree blob");

    const machine = dtRoot.node.getProperty("model") orelse @panic("Invalid device tree");
    kio.log("Machine model: {s}", .{machine});

    const frameRegions = mm.getFrameRegions(allocator, &dtRoot) catch
        @panic("Failed to initalize physical memory allocator");

    phys.init(allocator, frameRegions) catch
        @panic("Failed to initialize physical frame allocator");

    allocator.free(frameRegions);

    while (true) {}
}
