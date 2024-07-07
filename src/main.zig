const kio = @import("kio.zig");

export var deviceTreePointer: *void = undefined;

export fn kmain() void {
    kio.log("hello world! {}", .{deviceTreePointer});

    while (true) {}
}
