const fmt = @import("std").fmt;
const Writer = @import("std").io.GenericWriter;
const Reader = @import("std").io.GenericReader;

const sbi = @import("arch/riscv64/sbi.zig");
const time = @import("time.zig");

pub const KernelWriterType = Writer(void, error{}, writeBytes);
pub const kernelWriter = KernelWriterType{ .context = {} };

fn writeBytes(_: void, bytes: []const u8) error{}!usize {
    sbi.debugConsoleWrite(bytes) catch unreachable;
    return bytes.len;
}

pub fn log(comptime format: []const u8, args: anytype) void {
    const ns = time.nanoseconds() orelse 0;
    const sec = ns / time.NanosecondsPerSecond;
    const rem = ns / (10 * time.NanosecondsPerMicroseconds);
    fmt.format(kernelWriter, "[{: >5}.{:0>4}] ", .{ sec, rem }) catch unreachable;
    fmt.format(kernelWriter, format, args) catch unreachable;
    kernelWriter.writeByte('\n') catch unreachable;
}
