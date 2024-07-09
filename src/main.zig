const kio = @import("kio.zig");
const dt = @import("devicetree.zig");
const std = @import("std");

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
    var fba = std.heap.FixedBufferAllocator.init(&temporaryHeap);
    const allocator = fba.allocator();

    dt.readDeviceTreeBlob(allocator, deviceTreePointer) catch @panic("Failed to read device tree blob");

    while (true) {}
}
