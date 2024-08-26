const std = @import("std");
const builtin = @import("builtin");
const kio = @import("kio.zig");
const dt = @import("devicetree.zig");
const mm = @import("mem/mm.zig");
const phys = @import("mem/phys.zig");
const arch = @import("arch/arch.zig");
const time = @import("time.zig");
const uart = @import("drivers/uart.zig");

export var device_tree_pointer: *void = undefined;

const temp_heap_size = 65535;
var temp_heap: [temp_heap_size]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&temp_heap);
const static_mem_allocator = fba.allocator();

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    _ = error_return_trace;

    kio.err("KERNEL PANIC: {s}", .{msg});
    kio.err("Stack trace:", .{});
    const first_trace_addr = @returnAddress();
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |addr| {
        kio.err("    0x{x}", .{addr});
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
    kio.info("Device tree address: 0x{x}", .{@intFromPtr(device_tree_pointer)});
    const dt_root = dt.readDeviceTreeBlob(static_mem_allocator, device_tree_pointer) catch
        @panic("Failed to read device tree blob");

    uart.init(&dt_root) catch @panic("Failed to initialzie UART driver");

    const machine = dt_root.node.getProperty("model") orelse @panic("Invalid device tree");
    kio.info("Machine model: {s}", .{machine});

    const frame_regions = mm.getFrameRegions(static_mem_allocator, &dt_root) catch
        @panic("Failed to initalize physical memory allocator");

    phys.init(static_mem_allocator, frame_regions) catch
        @panic("Failed to initialize physical frame allocator");

    static_mem_allocator.free(frame_regions);

    arch.initInterrupts();

    time.init(&dt_root) catch @panic("Failed to initialize timer");

    arch.enableInterrupts();

    while (true) {
        asm volatile ("wfi");
    }
}
