const kio = @import("kio.zig");
const dtb = @import("dtb.zig");
const std = @import("std");

export var deviceTreePointer: *void = undefined;

pub fn panic(msg: []const u8, errorReturnTrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    kio.log("KERNEL PANIC: {s}", .{msg});
    _ = errorReturnTrace;
    _ = ret_addr;
    while (true) {}
}

export fn kmain() void {
    kio.log("hello world! {}", .{deviceTreePointer});
    dtb.readDeviceTreeBlob(deviceTreePointer) catch @panic("Failed to read device tree blob");

    while (true) {}
}
