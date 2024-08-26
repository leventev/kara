const time = @import("../../time.zig");
const dt = @import("../../devicetree.zig");
const csr = @import("csr.zig").CSR;
const sbi = @import("sbi.zig");
const trap = @import("trap.zig");

pub const riscv_clock_source = time.ClockSource{
    .init = init,
    .enable = enable,
    .disable = disable,
    .readCounter = readCounter,
};

// only written once
var counter_cmp: u64 = undefined;

fn init(dt_root: *const dt.DeviceTreeRoot) time.ClockSourceInitError!u64 {
    const cpus = dt_root.node.getChild("cpus") orelse
        return error.InvalidDeviceTree;
    const frequency = cpus.getPropertyU32("timebase-frequency") orelse
        return error.InvalidDeviceTree;

    const ns_per_increment = time.ns_per_second / frequency;
    counter_cmp = time.ns_per_tick / ns_per_increment;

    return frequency;
}

fn enable() void {
    const current_time = csr.time.read();
    const val = current_time + counter_cmp;
    sbi.setTimer(val);
    trap.enableInterrupt(@intCast(@intFromEnum(trap.InterruptCode.supervisor_timer)));
}

fn disable() void {
    trap.disableInterrupt(@intCast(@intFromEnum(trap.InterruptCode.supervisor_timer)));
}

fn readCounter() u64 {
    return csr.time.read();
}

pub fn tick() void {
    time.tick();
    trap.clearPendingInterrupt(@intFromEnum(trap.InterruptCode.supervisor_timer));
    const current_time = csr.time.read();
    const val = current_time + counter_cmp;
    sbi.setTimer(val);
}
