const std = @import("std");

const sbi = @import("arch/riscv64/sbi.zig");
const time = @import("time.zig");

pub const KernelWriterType = std.io.GenericWriter(void, error{}, writeBytes);
pub const kernel_writer = KernelWriterType{ .context = {} };

const kio_cfg: std.io.tty.Config = .escape_codes;

fn printTimeAndLogLevel(level: LogLevel) !void {
    const ns = time.nanoseconds() orelse 0;
    const sec = ns / time.ns_per_second;
    const rem = ns % time.ns_per_second;
    const qs = rem / (10 * time.ns_per_microseconds);

    try std.fmt.format(kernel_writer, "{}.{:0>5} ", .{ sec, qs });

    try kio_cfg.setColor(kernel_writer, std.io.tty.Color.bold);
    try kio_cfg.setColor(kernel_writer, level.color());
    _ = try kernel_writer.write(@tagName(level) ++ " ");
    try kio_cfg.setColor(kernel_writer, std.io.tty.Color.reset);
}

fn writeBytes(_: void, bytes: []const u8) error{}!usize {
    //if (uart.initialized) {
    //    uart.writeBytes(bytes);
    //} else {
    sbi.debugConsoleWrite(bytes) catch unreachable;
    //}

    return bytes.len;
}

pub const LogLevel = enum(comptime_int) {
    info,
    debug,
    warn,
    err,

    const Self = @This();

    fn color(self: Self) std.io.tty.Color {
        return switch (self) {
            .info => .blue,
            .debug => .magenta,
            .warn => .yellow,
            .err => .red,
        };
    }
};

pub fn print(level: LogLevel, comptime format: []const u8, args: anytype) void {
    printTimeAndLogLevel(level) catch unreachable;
    std.fmt.format(kernel_writer, format, args) catch unreachable;
    kernel_writer.writeByte('\n') catch unreachable;
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    print(.debug, format, args);
}

pub fn info(comptime format: []const u8, args: anytype) void {
    print(.info, format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    print(.warn, format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
    print(.err, format, args);
}
