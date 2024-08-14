const std = @import("std");
const kio = @import("kio.zig");
const dt = @import("devicetree.zig");
const mm = @import("mem/mm.zig");
const phys = @import("mem/phys.zig");
const arch = @import("arch/arch.zig");

export var deviceTreePointer: *void = undefined;

const temporaryHeapSize = 65535;
var temporaryHeap: [temporaryHeapSize]u8 = undefined;

pub fn panic(msg: []const u8, errorReturnTrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    _ = errorReturnTrace;

    kio.log("KERNEL PANIC: {s}", .{msg});
    kio.log("Stack trace:", .{});
    const firstTraceAddr = @returnAddress();
    var it = std.debug.StackIterator.init(firstTraceAddr, null);
    while (it.next()) |addr| {
        kio.log("    0x{x}", .{addr});
    }
    while (true) {}
}

export fn kmain() linksection(".init") void {
    // at this point virtual memory is still disabled
    arch.init();
    // virtual memory has been enabled
    init();
}

fn init() void {
    var fba = std.heap.FixedBufferAllocator.init(&temporaryHeap);
    const allocator = fba.allocator();

    kio.log("Device tree address: 0x{x}", .{@intFromPtr(deviceTreePointer)});
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
