const std = @import("std");
const dt = @import("devicetree.zig");
const kio = @import("kio.zig");
const arch = @import("arch/arch.zig");

pub const NanosecondsPerMicroseconds = 1_000;
pub const NanosecondsPerMilliseconds = 1_000_000;
pub const NanosecondsPerSecond = 1_000_000_000;
pub const NanosecondsPerTick = 1_000_000;

pub const ClockSourceInitError = error{InvalidDeviceTree};

pub const ClockSource = struct {
    init: *const fn (dtRoot: *const dt.DeviceTreeRoot) ClockSourceInitError!u64,
    enable: *const fn () void,
    disable: *const fn () void,
    readCounter: *const fn () u64,
};

// TODO: locking
const Timer = struct {
    initialized: bool,
    nsPerIncrement: u64,
    startCount: u64,

    const Self = @This();

    fn init(self: *Self, dtRoot: *const dt.DeviceTreeRoot) !void {
        const frequency = try arch.clockSource.init(dtRoot);
        self.nsPerIncrement = NanosecondsPerSecond / frequency;

        self.startCount = arch.clockSource.readCounter();
        self.initialized = true;

        kio.info("Timer initialized frequency={}Hz, increments every {}ns", .{
            frequency,
            self.nsPerIncrement,
        });
    }
};

var timer: Timer = undefined;

pub fn enable() void {
    std.debug.assert(timer.initialized);
    arch.clockSource.enable();
}

pub fn disable() void {
    std.debug.assert(timer.initialized);
    arch.clockSource.disable();
}

pub fn tick() void {
    std.debug.assert(timer.initialized);
    // TODO: scheduling
}

pub fn nanoseconds() ?u64 {
    if (!timer.initialized) return null;
    const current = arch.clockSource.readCounter();
    return (current - timer.startCount) * timer.nsPerIncrement;
}

pub fn init(dtRoot: *const dt.DeviceTreeRoot) !void {
    std.debug.assert(!timer.initialized);
    try timer.init(dtRoot);
    enable();
}
