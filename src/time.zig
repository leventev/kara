const std = @import("std");
const dt = @import("devicetree.zig");
const kio = @import("kio.zig");
const arch = @import("arch/arch.zig");

pub const ns_per_microseconds = 1_000;
pub const ns_per_milliseconds = 1_000_000;
pub const ns_per_second = 1_000_000_000;
pub const ns_per_tick = 1_000_000;

pub const ClockSourceInitError = error{InvalidDeviceTree};

pub const ClockSource = struct {
    init: *const fn (dt_root: *const dt.DeviceTreeRoot) ClockSourceInitError!u64,
    enable: *const fn () void,
    disable: *const fn () void,
    readCounter: *const fn () u64,
};

// TODO: locking
const Timer = struct {
    initialized: bool,
    ns_per_increment: u64,
    start_count: u64,

    const Self = @This();

    fn init(self: *Self, dt_root: *const dt.DeviceTreeRoot) !void {
        const frequency = try arch.clock_source.init(dt_root);
        self.ns_per_increment = ns_per_second / frequency;

        self.start_count = arch.clock_source.readCounter();
        self.initialized = true;

        kio.info("Timer initialized frequency={}Hz, increments every {}ns", .{
            frequency,
            self.ns_per_increment,
        });
    }
};

var timer: Timer = undefined;

pub fn enable() void {
    std.debug.assert(timer.initialized);
    arch.clock_source.enable();
}

pub fn disable() void {
    std.debug.assert(timer.initialized);
    arch.clock_source.disable();
}

pub fn tick() void {
    std.debug.assert(timer.initialized);
    // TODO: scheduling
}

pub fn nanoseconds() ?u64 {
    if (!timer.initialized) return null;
    const current = arch.clock_source.readCounter();
    return (current - timer.start_count) * timer.ns_per_increment;
}

pub fn init(dt_root: *const dt.DeviceTreeRoot) !void {
    std.debug.assert(!timer.initialized);
    try timer.init(dt_root);
    enable();
}
