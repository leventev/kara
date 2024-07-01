// documentation: https://github.com/riscv-non-isa/riscv-sbi-doc

pub const SBIDebugConsoleExtID = 0x4442434E;
pub const SBIDebugConsoleConWrite = 0;

pub fn sbi_call(extension: u64, function: u64, arg0: u64, arg1: u64, arg2: u64) !void {
    var val: u64 = undefined;
    var errorCode: u64 = undefined;
    asm volatile ("ecall"
        :
        : [extension] "{a7}" (extension),
          [function] "{a6}" (function),
          [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
    );

    // https://github.com/ziglang/zig/issues/215 :(
    asm volatile (""
        : [errorCode] "={a0}" (errorCode),
    );
    asm volatile (""
        : [val] "={a1}" (val),
    );
}

pub fn sbi_debug_console_write(str: []const u8) void {
    const addr_int = @intFromPtr(str.ptr);
    try sbi_call(SBIDebugConsoleExtID, SBIDebugConsoleConWrite, str.len, addr_int, 0);
}
