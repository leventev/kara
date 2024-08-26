const time = @import("../../time.zig");
const dt = @import("../../devicetree.zig");
const csr = @import("csr.zig").CSR;
const sbi = @import("sbi.zig");
const trap = @import("trap.zig");

pub const riscvClockSource = time.ClockSource{
    .init = init,
    .enable = enable,
    .disable = disable,
    .readCounter = readCounter,
};

// only written once
var counterCmp: u64 = undefined;

fn init(dtRoot: *const dt.DeviceTreeRoot) time.ClockSourceInitError!u64 {
    const cpus = dtRoot.node.getChild("cpus") orelse
        return error.InvalidDeviceTree;
    const frequency = cpus.getPropertyU32("timebase-frequency") orelse
        return error.InvalidDeviceTree;

    const nsPerIncrement = time.NanosecondsPerSecond / frequency;
    counterCmp = time.NanosecondsPerTick / nsPerIncrement;

    return frequency;
}

fn enable() void {
    const currentTime = csr.time.read();
    const val = currentTime + counterCmp;
    sbi.setTimer(val);
    trap.enableInterrupt(@intCast(@intFromEnum(trap.InterruptCode.SupervisorTimerInterrupt)));
}

fn disable() void {
    trap.disableInterrupt(@intCast(@intFromEnum(trap.InterruptCode.SupervisorTimerInterrupt)));
}

fn readCounter() u64 {
    return csr.time.read();
}

pub fn tick() void {
    time.tick();
    trap.clearPendingInterrupt(@intFromEnum(trap.InterruptCode.SupervisorTimerInterrupt));
    const currentTime = csr.time.read();
    const val = currentTime + counterCmp;
    sbi.setTimer(val);
}
