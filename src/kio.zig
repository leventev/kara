const fmt = @import("std").fmt;
const Writer = @import("std").io.GenericWriter;
const Reader = @import("std").io.GenericReader;

const sbi = @import("arch/riscv64/sbi.zig");

pub const KernelWriterType = Writer(void, error{}, writeBytes);
pub const kernelWriter = KernelWriterType{ .context = {} };

fn writeBytes(_: void, bytes: []const u8) error{}!usize {
    sbi.debugConsoleWrite(bytes) catch unreachable;
    return bytes.len;
}

pub fn log(comptime format: []const u8, args: anytype) void {
    fmt.format(kernelWriter, format, args) catch unreachable;
    kernelWriter.writeByte('\n') catch unreachable;
}
