// documentation: https://github.com/riscv-non-isa/riscv-sbi-doc

pub const SBIBaseExtID = 0x10;
pub const SBIGetSpecificationVersion = 0;
pub const SBIGetImplementationID = 1;
pub const SBIGetImplementationVersion = 2;

pub const SBIDebugConsoleExtID = 0x4442434E;
pub const SBIDebugConsoleConWrite = 0;

pub const SBITimerExtID = 0x54494D45;
pub const SBITimerSetTimer = 0;

pub const SBIImplementations: []const []const u8 = &.{
    "Berkeley Boot Loader (BBL)",
    "OpenSBI",
    "Xvisor",
    "KVM",
    "RustSBI",
    "Diosix",
    "Coffer",
    "Xen Project",
    "PolarFire Hart Software Services",
    "coreboot",
    "oreboot",
    "bhyve",
};

const SBIErrorCode = enum(i64) {
    SBI_SUCCESS = 0,
    SBI_ERR_FAILED = 1,
    SBI_ERR_NOT_SUPPORTED = 2,
    SBI_ERR_INVALID_PARAM = 3,
    SBI_ERR_DENIED = 4,
    SBI_ERR_INVALID_ADDRESS = 5,
    SBI_ERR_ALREADY_AVAILABLE = 6,
    SBI_ERR_ALREADY_STARTED = 7,
    SBI_ERR_ALREADY_STOPPED = 8,
    SBI_ERR_NO_SHMEM = 9,
    SBI_ERR_INVALID_STATE = 10,
    SBI_ERR_BAD_RANGE = 11,
};

const SBIError = error{
    Failed,
    NotSupported,
    InvalidParam,
    Denied,
    InvalidAddress,
    AlreadyAvailable,
    AlreadyStarted,
    AlreadyStopped,
    NoSharedMemory,
    InvalidState,
    BadRange,
};

pub fn call(extension: u64, function: u64, arg0: u64, arg1: u64, arg2: u64) SBIError!i64 {
    var val: i64 = undefined;
    var errorCodeVal: i64 = undefined;
    asm volatile ("ecall"
        :
        : [extension] "{a7}" (extension),
          [function] "{a6}" (function),
          [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
    );

    // TODO: https://github.com/ziglang/zig/issues/215 :(
    asm volatile (""
        : [errorCodeVal] "={a0}" (errorCodeVal),
    );
    asm volatile (""
        : [val] "={a1}" (val),
    );

    const errorCode: SBIErrorCode = @enumFromInt(errorCodeVal);

    switch (errorCode) {
        .SBI_SUCCESS => return val,
        .SBI_ERR_FAILED => return error.Failed,
        .SBI_ERR_NOT_SUPPORTED => return error.NotSupported,
        .SBI_ERR_INVALID_PARAM => return error.InvalidParam,
        .SBI_ERR_DENIED => return error.Denied,
        .SBI_ERR_INVALID_ADDRESS => return error.InvalidAddress,
        .SBI_ERR_ALREADY_AVAILABLE => return error.AlreadyAvailable,
        .SBI_ERR_ALREADY_STARTED => return error.AlreadyStarted,
        .SBI_ERR_ALREADY_STOPPED => return error.AlreadyStopped,
        .SBI_ERR_NO_SHMEM => return error.NoSharedMemory,
        .SBI_ERR_INVALID_STATE => return error.InvalidState,
        .SBI_ERR_BAD_RANGE => return error.BadRange,
    }
}

pub fn debugConsoleWrite(str: []const u8) SBIError!void {
    const addr_int = @intFromPtr(str.ptr);
    _ = try call(SBIDebugConsoleExtID, SBIDebugConsoleConWrite, str.len, addr_int, 0);
}

pub fn getSpecificationVersion() u64 {
    const res = call(SBIBaseExtID, SBIGetSpecificationVersion, 0, 0, 0) catch unreachable;
    return @intCast(res);
}

pub fn getImplementationID() u64 {
    const res = call(SBIBaseExtID, SBIGetImplementationID, 0, 0, 0) catch unreachable;
    return @intCast(res);
}

pub fn getImplementationVersion() u64 {
    const res = call(SBIBaseExtID, SBIGetImplementationVersion, 0, 0, 0) catch unreachable;
    return @intCast(res);
}

pub fn setTimer(stime: u64) void {
    _ = call(SBITimerExtID, SBITimerSetTimer, stime, 0, 0) catch unreachable;
}
