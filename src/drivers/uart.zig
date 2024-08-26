// https://uart16550.readthedocs.io/_/downloads/en/latest/pdf/

const std = @import("std");
const dt = @import("../devicetree.zig");
const mm = @import("../mem/mm.zig");

const ReceiverBufferRegisterOffset = 0;
const TransmissionHoldingRegisterOffset = 0;
const InterruptEnableRegisterOffset = 1;
const InterruptIdentificationRegisterOffset = 2;
const FIFOControlRegisterOffset = 2;
const LineControlRegisterOffset = 3;
const ModemControlRegisterOffset = 4;
const LineStatusRegisterOffset = 5;
const ModemStatusRegisterOffset = 6;

const DivisorLatchLowOffset = 0;
const DivisorLatchHighOffset = 1;

const InterruptEnableRegister = packed struct(u8) {
    receivedDataAvailableInterrupt: bool,
    transmitterHoldingRegisterInterrupt: bool,
    receiverLineStatusInterrupt: bool,
    modemStatusInterrupt: bool,
    __reserved: u4,
};

const InterruptIdentificationRegister = enum(u8) {
    ModemStatus = 0, // 4th priority
    TransmitterHoldingRegister = 1, // 3rd priority
    ReceiverDataAvailable = 4, // 2nd priority
    TimeoutIndication = 6, // 2nd priority
    ReceiverLineStatus = 3, // 1st priority
};

const FIFOControlRegister = packed struct(u8) {
    __ignored1: u1,
    clearReceiverFIFO: bool,
    clearTransmitFIFIO: bool,
    __ignored2: u3,
    triggerLevel: TriggerLevel,

    const TriggerLevel = enum(u2) {
        bytes1 = 0,
        bytes4 = 1,
        bytes8 = 2,
        bytes14 = 3,
    };
};

const LineControlRegister = packed struct(u8) {
    bits: Bits,
    extraStopBit: bool,
    parityEnable: bool,
    evenParitySelect: bool,
    stickParity: bool,
    breakControl: bool,
    divisorLatchAccess: bool,

    const Bits = enum(u2) {
        bits5 = 0,
        bits6 = 1,
        bits7 = 2,
        bits8 = 3,
    };
};

const ModemControlRegister = packed struct(u8) {
    dataTerminalReady: bool,
    requestToSend: bool,
    out1: u1,
    out2: u1,
    loopbackMode: bool,
    __ignored: u3,
};

const LineStatusRegister = packed struct(u8) {
    dataReady: bool,
    overrunError: bool,
    parityError: bool,
    framingError: bool,
    breakInterrupt: bool,
    transmitFIFOEmpty: bool,
    transmitterEmpty: bool,
    errorIndicationReceived: bool,
};

const ModemStatusRegister = packed struct(u8) {
    deltaClearToSend: bool,
    deltaDataSetReady: bool,
    trailingEdgeOfRingIndicator: bool,
    deltaDataCarrier: bool,
    ctsComplement: u1,
    dsrComplement: u1,
    riComplement: u1,
    dcdComplement: u1,
};

var basePtr: [*]u8 = undefined;

inline fn writeReg(reg: u8, val: u8) void {
    std.debug.assert(reg < 8);
    basePtr[reg] = val;
}

inline fn readReg(reg: u8) u8 {
    std.debug.assert(reg < 8);
    return basePtr[reg];
}

inline fn writeByte(val: u8) void {
    writeReg(TransmissionHoldingRegisterOffset, val);
}

pub fn writeBytes(buf: []const u8) void {
    var status: LineStatusRegister = @bitCast(readReg(LineStatusRegisterOffset));
    for (buf) |c| {
        while (!status.transmitFIFOEmpty) {
            status = @bitCast(readReg(LineStatusRegisterOffset));
        }
        writeByte(c);
    }
}

pub var initialized = false;

pub fn init(dtRoot: *const dt.DeviceTreeRoot) !void {
    const soc = dtRoot.node.getChild("soc") orelse
        return error.InvalidDeviceTree;

    const serial = soc.getChild("serial@10000000") orelse
        return error.InvalidDeviceTree;

    const freq = serial.getPropertyU32("clock-frequency") orelse
        return error.InvalidDeviceTree;
    _ = freq;

    const regs = serial.getProperty("reg") orelse
        return error.InvalidDeviceTree;

    // TODO: parse all provided addresses? and based on the provided cell sizes
    const baseAddr = std.mem.readInt(u64, regs[0..8], .big);
    const physAddr = mm.PhysicalAddress.make(baseAddr);
    const virtAddr = mm.physicalToHHDMAddress(physAddr);
    basePtr = @ptrFromInt(virtAddr.asInt());

    writeReg(InterruptEnableRegisterOffset, 0);
    writeReg(InterruptIdentificationRegisterOffset, 0xC1);
    writeReg(ModemControlRegisterOffset, 0);
    writeReg(FIFOControlRegisterOffset, 0b11000000);

    // we only care about enabling DLAB
    writeReg(LineControlRegisterOffset, @bitCast(LineControlRegister{
        .divisorLatchAccess = true,
        .bits = .bits8,
        .breakControl = false,
        .evenParitySelect = false,
        .extraStopBit = false,
        .parityEnable = false,
        .stickParity = false,
    }));

    // TODO: calculate an actual divisor instead of hardcoding it
    const divisor: u16 = 592;

    writeReg(DivisorLatchHighOffset, @intCast(divisor >> 8));
    writeReg(DivisorLatchLowOffset, @intCast(divisor & 0xFF));

    writeReg(LineControlRegisterOffset, @bitCast(LineControlRegister{
        .divisorLatchAccess = false,
        .bits = .bits8,
        .breakControl = false,
        .evenParitySelect = false,
        .extraStopBit = false,
        .parityEnable = false,
        .stickParity = false,
    }));

    initialized = true;
}
