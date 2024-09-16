// https://uart16550.readthedocs.io/_/downloads/en/latest/pdf/

const std = @import("std");
const devicetree = @import("../devicetree.zig");
const mm = @import("../mem/mm.zig");

const receiver_buffer_offset = 0;
const transmission_holding_register_offset = 0;
const interrupt_enable_offset = 1;
const interrupt_identification_offset = 2;
const fifo_control_offset = 2;
const line_control_offset = 3;
const modem_control_offset = 4;
const line_status_offset = 5;
const modem_status_offset = 6;

const divisior_latch_low_offset = 0;
const divisior_latch_high_offset = 1;

const InterruptEnableRegister = packed struct(u8) {
    received_data_available: bool,
    transmitter_holding_register: bool,
    receiver_line_status: bool,
    modem_status_interrupt: bool,
    __reserved: u4,
};

const InterruptIdentificationRegister = enum(u8) {
    modem_status = 0, // 4th priority
    transmitter_holding_register = 1, // 3rd priority
    receiver_data_available = 4, // 2nd priority
    timeout_indication = 6, // 2nd priority
    rceiver_line_status = 3, // 1st priority
};

const FIFOControlRegister = packed struct(u8) {
    __ignored1: u1,
    clear_receiver_fifo: bool,
    clear_transmit_fifo: bool,
    __ignored2: u3,
    trigger_level: TriggerLevel,

    const TriggerLevel = enum(u2) {
        bytes1 = 0,
        bytes4 = 1,
        bytes8 = 2,
        bytes14 = 3,
    };
};

const LineControlRegister = packed struct(u8) {
    bits: Bits,
    extra_stop_bit: bool,
    parity_enable: bool,
    even_parity_select: bool,
    stick_parity: bool,
    break_control: bool,
    divisior_latch_access: bool,

    const Bits = enum(u2) {
        bits5 = 0,
        bits6 = 1,
        bits7 = 2,
        bits8 = 3,
    };
};

const ModemControlRegister = packed struct(u8) {
    data_terminal_ready: bool,
    request_to_send: bool,
    out1: u1,
    out2: u1,
    loopback_mode: bool,
    __ignored: u3,
};

const LineStatusRegister = packed struct(u8) {
    data_ready: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_interrupt: bool,
    transmit_fifo_empty: bool,
    transmitter_empty: bool,
    err: bool,
};

const ModemStatusRegister = packed struct(u8) {
    delta_clear_to_send: bool,
    delta_data_set_ready: bool,
    trailing_edge_of_ring_indicator: bool,
    delta_data_carrier: bool,
    cts_complement: u1,
    dsr_complement: u1,
    ri_complement: u1,
    dcd_complement: u1,
};

var base_ptr: [*]u8 = undefined;

inline fn writeReg(reg: u8, val: u8) void {
    std.debug.assert(reg < 8);
    base_ptr[reg] = val;
}

inline fn readReg(reg: u8) u8 {
    std.debug.assert(reg < 8);
    return base_ptr[reg];
}

inline fn writeByte(val: u8) void {
    writeReg(transmission_holding_register_offset, val);
}

pub fn writeBytes(buf: []const u8) void {
    var status: LineStatusRegister = @bitCast(readReg(line_status_offset));
    for (buf) |c| {
        while (!status.transmit_fifo_empty) {
            status = @bitCast(readReg(line_status_offset));
        }
        writeByte(c);
    }
}

pub var initialized = false;

pub fn init(dt: *const devicetree.DeviceTree) !void {
    const soc = dt.getChild(dt.root(), "soc") orelse
        return error.InvalidDeviceTree;

    const serial = dt.getChild(soc, "serial@10000000") orelse
        return error.InvalidDeviceTree;

    const freq = serial.getProperty(.clock_frequency) orelse
        return error.InvalidDeviceTree;
    _ = freq;

    const regs = serial.getProperty(.reg) orelse
        return error.InvalidDeviceTree;

    // TODO: get address cells from parent
    var regs_it = try regs.iterator(2, 0);

    // TODO: parse all provided addresses? and based on the provided cell sizes
    const baseAddr = (regs_it.next() orelse return error.InvalidDeviceTree).addr;
    const physAddr = mm.PhysicalAddress.make(baseAddr);
    const virtAddr = mm.physicalToHHDMAddress(physAddr);
    base_ptr = @ptrFromInt(virtAddr.asInt());

    writeReg(interrupt_enable_offset, 0);
    writeReg(interrupt_identification_offset, 0xC1);
    writeReg(modem_control_offset, 0);
    writeReg(fifo_control_offset, 0b11000000);

    // we only care about enabling DLAB
    writeReg(line_control_offset, @bitCast(LineControlRegister{
        .divisior_latch_access = true,
        .bits = .bits8,
        .break_control = false,
        .even_parity_select = false,
        .extra_stop_bit = false,
        .parity_enable = false,
        .stick_parity = false,
    }));

    // TODO: calculate an actual divisor instead of hardcoding it
    const divisor: u16 = 592;

    writeReg(divisior_latch_high_offset, @intCast(divisor >> 8));
    writeReg(divisior_latch_low_offset, @intCast(divisor & 0xFF));

    writeReg(line_control_offset, @bitCast(LineControlRegister{
        .divisior_latch_access = false,
        .bits = .bits8,
        .break_control = false,
        .even_parity_select = false,
        .extra_stop_bit = false,
        .parity_enable = false,
        .stick_parity = false,
    }));

    initialized = true;
}
