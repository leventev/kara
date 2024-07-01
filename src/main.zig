const sbi = @import("arch/riscv/sbi.zig");

export fn kmain() void {
    sbi.sbi_debug_console_write("hello world!");

    while (true) {}
}
