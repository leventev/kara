const std = @import("std");
const kio = @import("../../kio.zig");
const csr = @import("csr.zig").CSR;
const sbi = @import("sbi.zig");
const timer = @import("timer.zig");

extern fn trapHandlerSupervisor() void;

const TrapData = struct {
    gprs: [32]u64,

    const Self = @This();

    fn printGPR(self: Self, writer: kio.KernelWriterType, idx: usize) !void {
        std.debug.assert(idx < 32);

        const alternativeNames = [_][]const u8{
            "zr", "ra", "sp",  "gp",  "tp", "t0",
            "t1", "t2", "s0",  "s1",  "a0", "a1",
            "a2", "a3", "a4",  "a5",  "a6", "a7",
            "s2", "s3", "s4",  "s5",  "s6", "s7",
            "s8", "s9", "s10", "s11", "t3", "t4",
            "t5", "t6",
        };

        const name = alternativeNames[idx];
        var nameTotalLen = 2 + name.len;
        if (idx > 9) nameTotalLen += 1;

        const alignTo = 7;
        const rem = alignTo - nameTotalLen;

        try writer.print("x{}/{s}", .{ idx, name });
        try writer.writeByteNTimes(' ', rem);
        try writer.print("0x{x:0>16}", .{self.gprs[idx]});
    }

    fn printGPRs(self: Self, writer: kio.KernelWriterType) void {
        const totalRegs = 32;
        const regsPerLine = 4;
        const lines = totalRegs / regsPerLine;
        for (0..lines) |i| {
            for (0..regsPerLine) |j| {
                self.printGPR(writer, i * regsPerLine + j) catch unreachable;
                writer.writeByte(' ') catch unreachable;
            }
            writer.writeByte('\n') catch unreachable;
        }
    }
};

// TODO: per hart
var trapFrame = TrapData{
    .gprs = [_]u64{0} ** 32,
};

const TrapVectorBaseAddr = packed struct(u64) {
    mode: Mode,
    base: u62,

    const Mode = enum(u2) {
        Direct = 0,
        Vectored = 1,
    };
    // 0x80200228
    fn make(addr: u64, mode: Mode) TrapVectorBaseAddr {
        std.debug.assert(addr & 0b11 == 0);
        return .{
            .mode = mode,
            .base = @intCast(
                std.math.shr(
                    u64,
                    addr,
                    2,
                ),
            ),
        };
    }
};

const TrapCause = packed struct(u64) {
    code: u63,
    asynchronous: bool,

    const Self = @This();

    fn exception(self: Self) ExceptionCode {
        std.debug.assert(!self.asynchronous);
        return @enumFromInt(self.code);
    }

    fn interrupt(self: Self) InterruptCode {
        std.debug.assert(self.asynchronous);
        return @enumFromInt(self.code);
    }
};

const ExceptionCode = enum(u63) {
    InstructionAddressMisaligned = 0,
    InstructionAccessFault = 1,
    IllegalInstruction = 2,
    Breakpoint = 3,
    LoadAddressMisaligned = 4,
    LoadAccessFault = 5,
    StoreOrAMOAddressMisaligned = 6,
    StoreOrAMOAccessFault = 7,
    EcallUMode = 8,
    EcallSMode = 9,
    EcallMMode = 11, // read only fix 0
    InstructionPageFault = 12,
    LoadPageFault = 13,
    StoreOrAMOPageFault = 15,
    SoftwareCheck = 18,
    HardwareError = 19,
};

pub const InterruptCode = enum(u63) {
    SupervisorSoftwareInterrupt = 1,
    MachineSoftwareInterrupt = 3,
    SupervisorTimerInterrupt = 5,
    MachineTimerInterrupt = 7,
    SupervisorExternalInterrupt = 9,
    MachineExternalInterrupt = 11,
    CounterOverflowInterrupt = 13,
};

const MPP = enum(u2) {
    User = 0b00,
    Supervisor = 0b01,
    Reserved = 0b10,
    Machine = 0b11,
};

const SPP = enum(u1) {
    User = 0,
    Supervisor = 1,
};

const VectorStatus = enum(u2) {
    Off = 0,
    Initial = 1,
    Clean = 2,
    Dirty = 3,
};

const FloatStatus = enum(u2) {
    Off = 0,
    Initial = 1,
    Clean = 2,
    Dirty = 3,
};

const ExtraExtensionStatus = enum(u2) {
    AllOff = 0,
    NoneDirtyOrClean = 1,
    NoneDirtySomeClean = 2,
    SomeDirty = 3,
};

const MPRV = enum(u1) {
    Normal = 0,
    BehaveLikeMPP = 1,
};

const SUM = enum(u1) {
    Prohibited = 0,
    Permitted = 1,
};

const XLength = enum(u2) {
    X32 = 1,
    X64 = 2,
    X128 = 3,
};

const MStatus = packed struct(u64) {
    __reserved1: u1,
    supervisorInterruptEnable: bool,
    __reserved2: u1,
    machineInterruptEnable: bool,
    __reserved3: u1,
    supervisorPreviousInterruptEnable: bool,
    userBigEndian: bool,
    machinePreviousInterruptEnable: bool,
    supervisorPreviousPrivilege: SPP,
    vectorStatus: VectorStatus,
    machinePreviousPrivilege: MPP,
    floatStatus: FloatStatus,
    extraExtensionStatus: ExtraExtensionStatus,
    memoryPrivilege: MPRV,
    supervisorUserMemoryAccessable: bool,
    executableMemoryReadable: bool,
    trapVirtualMemory: bool,
    timeoutWait: bool,
    trapSret: bool,
    __reserved4: u9,
    userXLen: XLength,
    supervisorXLen: XLength,
    supervisorBigEndian: bool,
    machineBigEndian: bool,
    __reserved5: u25,
    stateDirty: bool,
};

const SStatus = packed struct(u64) {
    __reserved1: u1,
    supervisorInterruptEnable: bool,
    __reserved2: u3,
    supervisorPreviousInterruptEnable: bool,
    userBigEndian: bool,
    __reserved3: u1,
    supervisorPreviousPrivilege: SPP,
    vectorStatus: VectorStatus,
    __reserved4: u2,
    floatStatus: FloatStatus,
    extraExtensionStatus: ExtraExtensionStatus,
    __reserved5: u1,
    supervisorUserMemoryAccessable: bool,
    executableMemoryReadable: bool,
    __reserved6: u12,
    userXLen: XLength,
    __reserved7: u29,
    stateDirty: bool,

    const Self = @This();

    fn print(self: Self, writer: kio.KernelWriterType) void {
        writer.print("SIE={} SPIE={} SPP={}\n", .{
            self.supervisorInterruptEnable,
            self.supervisorPreviousInterruptEnable,
            self.supervisorPreviousPrivilege,
        }) catch unreachable;

        writer.print("VS={s} FS={s} XS={s} SD={}\n", .{
            @tagName(self.vectorStatus),
            @tagName(self.floatStatus),
            @tagName(self.extraExtensionStatus),
            self.stateDirty,
        }) catch unreachable;

        writer.print("SUM={} MXR={} UXL={} UBE={}\n", .{
            self.supervisorUserMemoryAccessable,
            self.executableMemoryReadable,
            self.supervisorUserMemoryAccessable,
            self.userBigEndian,
        }) catch unreachable;
    }
};

pub fn enableInterrupts() void {
    csr.sstatus.setBits(1 << @bitOffsetOf(SStatus, "supervisorInterruptEnable"));
}

pub fn disableInterrupts() void {
    csr.sstatus.clearBits(1 << @bitOffsetOf(SStatus, "supervisorInterruptEnable"));
}

pub fn enableInterrupt(id: usize) void {
    std.debug.assert(id < 64);
    csr.sie.setBits(std.math.shl(u64, 1, id));
}

pub fn disableInterrupt(id: usize) void {
    std.debug.assert(id < 64);
    csr.sie.clearBits(std.math.shl(u64, 1, id));
}

pub fn clearPendingInterrupt(id: usize) void {
    std.debug.assert(id < 64);
    csr.sip.clearBits(std.math.shl(u64, 1, id));
}

fn genericExceptionHandler(code: ExceptionCode, pc: u64, status: SStatus, tval: u64, frame: *TrapData) void {
    status.print(kio.kernelWriter);
    frame.printGPRs(kio.kernelWriter);
    kio.log("PC=0x{x}", .{pc});
    kio.log("Trap value: 0x{x}", .{tval});
    @panic(@tagName(code));
}

fn handleException(code: ExceptionCode, pc: u64, status: SStatus, tval: u64, frame: *TrapData) void {
    switch (code) {
        .LoadPageFault, .InstructionPageFault, .StoreOrAMOPageFault => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            kio.log("Faulting address: 0x{x}", .{tval});
            @panic("Page fault");
        },
        .EcallUMode => {
            @panic("TODO");
        },
        .EcallSMode => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            kio.log("Trap value: 0x{x}", .{tval});
            @panic("Environment call from S mode");
        },
        .EcallMMode => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            kio.log("Trap value: 0x{x}", .{tval});
            @panic("Environment call from M mode");
        },
        else => genericExceptionHandler(code, pc, status, tval, frame),
    }
}

fn handleInterrupt(code: InterruptCode, pc: u64, status: SStatus, tval: u64, frame: *TrapData) void {
    _ = tval;
    switch (code) {
        .SupervisorSoftwareInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Supervisor software interrupt");
        },
        .MachineSoftwareInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Machine software interrupt");
        },
        .SupervisorTimerInterrupt => {
            timer.tick();
        },
        .MachineTimerInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Machine timer interrupt");
        },
        .SupervisorExternalInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Supervisor external interrupt");
        },
        .MachineExternalInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Machine external interrupt");
        },
        .CounterOverflowInterrupt => {
            status.print(kio.kernelWriter);
            frame.printGPRs(kio.kernelWriter);
            kio.log("PC=0x{x}", .{pc});
            @panic("Counter overflow interrupt");
        },
    }
}

export fn handleTrap(
    epc: u64,
    cause: TrapCause,
    status: SStatus,
    tval: u64,
    frame: *TrapData,
) void {
    if (cause.asynchronous) {
        handleInterrupt(cause.interrupt(), epc, status, tval, frame);
    } else {
        handleException(cause.exception(), epc, status, tval, frame);
    }
}

pub fn init() void {
    const stvec = TrapVectorBaseAddr.make(
        @intFromPtr(&trapHandlerSupervisor),
        TrapVectorBaseAddr.Mode.Direct,
    );

    csr.stvec.write(@bitCast(stvec));
    csr.sscratch.write(@intFromPtr(&trapFrame));
}
