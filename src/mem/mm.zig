const std = @import("std");
const kio = @import("../kio.zig");
const dt = @import("../devicetree.zig");
const arch = @import("../arch/arch.zig");

const bigToNative = std.mem.bigToNative;

// these addresses of these symbols can be used to
// calculate the sizes of the loaded sections
// TODO: maybe put these definitions in another file
extern const __kernel_start: u8;
extern const __kernel_end: u8;
extern const __text_start: u8;
extern const __text_end: u8;
extern const __data_start: u8;
extern const __data_end: u8;
extern const __rodata_start: u8;
extern const __rodata_end: u8;
extern const __bss_start: u8;
extern const __bss_end: u8;
extern const __stack_start: u8;
extern const __stack_end: u8;

pub const page_size = 4096;
pub const frame_size = page_size;

pub const entries_per_table = 512;

pub const VirtualAddress = arch.VirtualAddress;
pub const PhysicalAddress = arch.PhysicalAddress;

// TODO: move all device tree specific code to devicetree.zig
pub const MemoryRegion = struct {
    start: u64,
    size: u64,

    const Self = @This();

    fn end(self: Self) u64 {
        return self.start + self.size;
    }

    fn intersects(self: Self, other: MemoryRegion) bool {
        return !(other.start >= self.end() or other.end() <= self.start);
    }
};

pub const PhysicalMemoryRegion = struct {
    range: MemoryRegion,
};

const ReservedMemoryRegion = struct {
    range: MemoryRegion,
    name: []const u8,
    no_map: bool,
    reusable: bool,
    system: bool,
    // TODO: support dynamic reservations too
};

fn calculateEntrySize(node: *const dt.DeviceTreeNode) !usize {
    const address_cells = node.getPropertyU32("#address-cells") orelse return error.InvalidDeviceTree;
    const size_cells = node.getPropertyU32("#size-cells") orelse return error.InvalidDeviceTree;

    const expected_cells = @sizeOf(u64) / @sizeOf(u32);
    if (address_cells != expected_cells or size_cells != expected_cells) {
        return error.UnexpectedCellCount;
    }

    const cells_per_entry = address_cells + size_cells;
    return cells_per_entry * @sizeOf(u32);
}

fn readMemoryPair(buff: []const u8, idx: usize, entrySize: usize) MemoryRegion {
    const entry_base = idx * entrySize;
    const entry = buff[entry_base .. entry_base + entrySize];

    const addr = std.mem.readInt(u64, entry[0..8], .big);
    const size = std.mem.readInt(u64, entry[8..16], .big);

    return MemoryRegion{ .start = addr, .size = size };
}

fn parseMemoryRegions(
    allocator: std.mem.Allocator,
    dt_root: *const dt.DeviceTreeNode,
) !std.ArrayListUnmanaged(PhysicalMemoryRegion) {
    const entry_size = try calculateEntrySize(dt_root);

    var regions = std.ArrayListUnmanaged(PhysicalMemoryRegion){};

    var iter = dt_root.children.iterator();
    while (iter.next()) |child| {
        if (!std.mem.startsWith(u8, child.key_ptr.*, "memory"))
            continue;

        var device_type = child.value_ptr.getProperty("device_type") orelse return error.InvalidDeviceTree;

        // cut off null terminator
        device_type = device_type[0 .. device_type.len - 1];
        if (!std.mem.eql(u8, device_type, "memory")) return error.InvalidDeviceTree;

        const reg = child.value_ptr.getProperty("reg") orelse return error.InvalidDeviceTree;
        const entry_count = reg.len / entry_size;

        for (0..entry_count) |i| {
            const entry = readMemoryPair(reg, i, entry_size);
            try regions.append(allocator, PhysicalMemoryRegion{ .range = entry });
        }
    }

    return regions;
}

fn parseReservedMemoryRegions(
    allocator: std.mem.Allocator,
    dt_root: *const dt.DeviceTreeNode,
) !std.ArrayListUnmanaged(ReservedMemoryRegion) {
    const reserved_memory = dt_root.getChild("reserved-memory") orelse return error.InvalidDeviceTree;

    const entry_size = try calculateEntrySize(reserved_memory);

    var regions = std.ArrayListUnmanaged(ReservedMemoryRegion){};

    var iter = reserved_memory.children.iterator();
    while (iter.next()) |region| {
        const node = region.value_ptr;

        const no_map = node.getProperty("no-map") != null;
        const reusable = node.getProperty("reusable") != null;

        const reg = region.value_ptr.getProperty("reg") orelse continue;
        const entry_count = reg.len / entry_size;

        for (0..entry_count) |i| {
            const entry = readMemoryPair(reg, i, entry_size);

            try regions.append(allocator, ReservedMemoryRegion{
                .range = entry,
                .name = region.key_ptr.*,
                .no_map = no_map,
                .reusable = reusable,
                .system = false,
            });
        }
    }

    return regions;
}

const minimum_region_size = 8 * 4096;

fn processRegion(
    regs: *std.ArrayList(MemoryRegion),
    region: PhysicalMemoryRegion,
    reserved_regions: []const ReservedMemoryRegion,
) !void {
    std.debug.assert(region.range.start % page_size == 0);
    std.debug.assert(region.range.size % page_size == 0);

    var range = region.range;

    for (reserved_regions) |resv| {
        std.debug.assert(resv.range.start % page_size == 0);
        std.debug.assert(resv.range.size % page_size == 0);

        if (!range.intersects(resv.range))
            continue;

        const resv_range = resv.range;

        const end = range.end();
        const resv_end = resv_range.end();

        // the reserved region starts before or at the same address as the physical region
        if (resv_range.start <= region.range.start) {
            // cut off the interescting part at the beginning of the region
            range.start = resv_end;
            range.size = end - range.start;

            continue;
        }

        // the reserved region ends after or at the same address as the physical region
        if (resv_end >= end) {
            // cut off the interescting part at the end of the region
            range.size = resv_range.start - range.start;

            continue;
        }

        // the reserved region is inside the physical region
        range.size = resv_range.start - range.start;

        // do the same process for the region on the right side of the reserved region
        const other_region = PhysicalMemoryRegion{
            .range = MemoryRegion{
                .start = resv_end,
                .size = end - resv_end,
            },
        };

        try processRegion(regs, other_region, reserved_regions);
    }

    if (range.size >= minimum_region_size)
        try regs.append(range);
}

fn getUsableRegions(
    allocator: std.mem.Allocator,
    physical_regions: []const PhysicalMemoryRegion,
    reserved_regions: []const ReservedMemoryRegion,
) !std.ArrayList(MemoryRegion) {
    var regions = std.ArrayList(MemoryRegion).init(allocator);

    for (physical_regions) |phys| {
        try processRegion(&regions, phys, reserved_regions);
    }

    return regions;
}

fn addKernelReservedMemory(
    allocator: std.mem.Allocator,
    reserved_regins: *std.ArrayListUnmanaged(ReservedMemoryRegion),
) !void {

    // we can(have to) align forward the end address of the segments because the next segment should be at the next possible 4K aligned address
    const text_start = @intFromPtr(&__text_start);
    const text_end = @intFromPtr(&__text_end);
    const text_size = text_end - text_start;

    const data_start = @intFromPtr(&__data_start);
    const data_end = @intFromPtr(&__data_end);
    const data_size = data_end - data_start;

    const rodata_start = @intFromPtr(&__rodata_start);
    const rodata_end = @intFromPtr(&__rodata_end);
    const rodata_size = rodata_end - rodata_start;

    const bss_start = @intFromPtr(&__bss_start);
    const bss_end = @intFromPtr(&__bss_end);
    const bss_size = bss_end - bss_start;

    const stack_start = @intFromPtr(&__stack_start);
    const stack_end = @intFromPtr(&__stack_end);
    const stack_size = stack_end - stack_start;

    const kernel_start = @intFromPtr(&__kernel_start);
    // we align forward so that the size of the region is divisible by 4K
    const kernel_end = std.mem.alignForward(usize, @intFromPtr(&__kernel_end), 4096);
    const kernel_size = kernel_end - kernel_start;

    kio.info("Kernel code: {} KiB, rodata: {} KiB, data: {} KiB, bss: {} KiB, stack: {} KiB", .{
        text_size / 1024,
        rodata_size / 1024,
        data_size / 1024,
        bss_size / 1024,
        stack_size / 1024,
    });

    try reserved_regins.append(allocator, ReservedMemoryRegion{
        .name = "kernel",
        .no_map = true,
        .reusable = false,
        .system = true,
        .range = MemoryRegion{
            .start = kernel_start,
            .size = kernel_size,
        },
    });
}

fn addDeviceTreeReservedMemory(
    allocator: std.mem.Allocator,
    reserved_regions: *std.ArrayListUnmanaged(ReservedMemoryRegion),
    dtRoot: *const dt.DeviceTreeRoot,
) !void {
    // we need to reserve memory for the DT itself
    const dt_start = std.mem.alignBackward(u64, @intCast(dtRoot.addr), 4096);
    const dt_end = std.mem.alignForward(u64, @intCast(dtRoot.addr + dtRoot.size), 4096);

    const dt_region = ReservedMemoryRegion{
        .name = "device-tree",
        .no_map = true,
        .reusable = false,
        .system = false,
        .range = MemoryRegion{
            .start = dt_start,
            .size = dt_end - dt_start,
        },
    };
    try reserved_regions.append(allocator, dt_region);
}

fn printPhysicalRegions(physical_regions: []const PhysicalMemoryRegion) void {
    kio.info("Physical memory regions:", .{});
    for (physical_regions) |reg| {
        const range = reg.range;
        const sizeInKiB = range.size / 1024;
        kio.info(
            "    [0x{x:0>16}-0x{x:0>16}] ({} KiB)",
            .{ range.start, range.end() - 1, sizeInKiB },
        );
    }
}

fn printReservedRegions(reserved_regions: []const ReservedMemoryRegion) void {
    kio.info("Reserved memory regions:", .{});
    for (reserved_regions) |reg| {
        const range = reg.range;
        const size_in_kib = range.size / 1024;
        if (reg.system) {
            kio.info("    [0x{x:0>16}-0x{x:0>16}] <{s}> ({} KiB) system", .{
                range.start,
                range.end() - 1,
                reg.name,
                size_in_kib,
            });
        } else {
            const no_map_string = if (reg.no_map) "no-map" else "map";
            const reusable_string = if (reg.reusable) "reusable" else "non-reusable";
            kio.info("    [0x{x:0>16}-0x{x:0>16}] <{s}> ({} KiB) {s} {s}", .{
                range.start,
                range.end() - 1,
                reg.name,
                size_in_kib,
                no_map_string,
                reusable_string,
            });
        }
    }
}

fn printUsableRegions(regions: []const MemoryRegion) void {
    kio.info("Usable memory regions:", .{});
    for (regions) |reg| {
        const size_in_kib = reg.size / 1024;
        kio.info(
            "    [0x{x:0>16}-0x{x:0>16}] ({} KiB)",
            .{ reg.start, reg.end() - 1, size_in_kib },
        );
    }
}

pub fn getFrameRegions(allocator: std.mem.Allocator, dt_root: *const dt.DeviceTreeRoot) ![]const MemoryRegion {
    var phyiscal_regions = try parseMemoryRegions(allocator, &dt_root.node);
    defer phyiscal_regions.deinit(allocator);

    var reserved_regions = try parseReservedMemoryRegions(allocator, &dt_root.node);
    defer reserved_regions.deinit(allocator);

    try addDeviceTreeReservedMemory(allocator, &reserved_regions, dt_root);
    try addKernelReservedMemory(allocator, &reserved_regions);

    printPhysicalRegions(phyiscal_regions.items);
    printReservedRegions(reserved_regions.items);

    var usable_regions = try getUsableRegions(
        allocator,
        phyiscal_regions.items,
        reserved_regions.items,
    );

    printUsableRegions(usable_regions.items);

    return usable_regions.toOwnedSlice();
}

const hhdm_start = 0xffffffc000000000;

pub fn physicalToHHDMAddress(phys: PhysicalAddress) VirtualAddress {
    return VirtualAddress.make(hhdm_start + phys.asInt());
}
