const Module = struct {
    name: []const u8,
    module: type,
    enabled: bool,
    init_type: ModuleType,

    const ModuleType = union(enum) {
        always_run,
        driver: Driver,
    };

    const Driver = struct {
        compatible: []const []const u8,
    };
};

pub const modules: []const Module = &.{
    .{
        .name = "uart",
        .module = @import("drivers/uart.zig"),
        .enabled = true,
        .init_type = Module.ModuleType{
            .driver = .{
                .compatible = &.{ "ns16550", "ns16550a" },
            },
        },
    },
};
