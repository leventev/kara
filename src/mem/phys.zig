const kio = @import("../kio.zig");
const dt = @import("../devicetree.zig");
const std = @import("std");

const bigToNative = std.mem.bigToNative;

// TODO: move all device tree specific code to devicetree.zig
const MemoryPair = struct {
    addr: u64,
    size: u64,
};

const PhysicalMemoryRegion = struct {
    range: MemoryPair,
};

const ReservedMemoryRegion = struct {
    range: MemoryPair,
    name: []const u8,
    noMap: bool,
    reusable: bool,
    // TODO: support dynamic reservations too
};

fn calculateEntrySize(node: *const dt.DeviceTreeNode) !usize {
    const addressCells = node.getPropertyU32("#address-cells") orelse return error.InvalidDeviceTree;
    const sizeCells = node.getPropertyU32("#size-cells") orelse return error.InvalidDeviceTree;

    const expectedCells = @sizeOf(u64) / @sizeOf(u32);
    if (addressCells != expectedCells or sizeCells != expectedCells) {
        return error.UnexpectedCellCount;
    }

    const cellsPerEntry = addressCells + sizeCells;
    return cellsPerEntry * @sizeOf(u32);
}

fn readMemoryPair(buff: []const u8, idx: usize, entrySize: usize) MemoryPair {
    const entryBase = idx * entrySize;
    const entry = buff[entryBase .. entryBase + entrySize];

    const addr = std.mem.readInt(u64, entry[0..8], .big);
    const size = std.mem.readInt(u64, entry[8..16], .big);

    return MemoryPair{ .addr = addr, .size = size };
}

fn parseMemoryRegions(allocator: std.mem.Allocator, dtRoot: *const dt.DeviceTreeNode) !std.ArrayListUnmanaged(PhysicalMemoryRegion) {
    const entrySize = try calculateEntrySize(dtRoot);

    var regions = std.ArrayListUnmanaged(PhysicalMemoryRegion){};

    var iter = dtRoot.children.iterator();
    while (iter.next()) |child| {
        if (!std.mem.startsWith(u8, child.key_ptr.*, "memory"))
            continue;

        var deviceType = child.value_ptr.getProperty("device_type") orelse return error.InvalidDeviceTree;

        // cut off null terminator
        deviceType = deviceType[0 .. deviceType.len - 1];
        if (!std.mem.eql(u8, deviceType, "memory")) return error.InvalidDeviceTree;

        const reg = child.value_ptr.getProperty("reg") orelse return error.InvalidDeviceTree;
        const entryCount = reg.len / entrySize;

        for (0..entryCount) |i| {
            const entry = readMemoryPair(reg, i, entrySize);
            try regions.append(allocator, PhysicalMemoryRegion{ .range = entry });
        }
    }

    return regions;
}

fn parseReservedMemoryRegions(allocator: std.mem.Allocator, dtRoot: *const dt.DeviceTreeNode) !std.ArrayListUnmanaged(ReservedMemoryRegion) {
    const reservedMemory = dtRoot.getChild("reserved-memory") orelse return error.InvalidDeviceTree;

    const entrySize = try calculateEntrySize(reservedMemory);

    var regions = std.ArrayListUnmanaged(ReservedMemoryRegion){};

    var iter = reservedMemory.children.iterator();
    while (iter.next()) |region| {
        const node = region.value_ptr;

        const noMap = node.getProperty("no-map") != null;
        const reusable = node.getProperty("reusable") != null;

        const reg = region.value_ptr.getProperty("reg") orelse continue;
        const entryCount = reg.len / entrySize;

        for (0..entryCount) |i| {
            const entry = readMemoryPair(reg, i, entrySize);

            try regions.append(allocator, ReservedMemoryRegion{
                .range = entry,
                .name = region.key_ptr.*,
                .noMap = noMap,
                .reusable = reusable,
            });
        }
    }

    return regions;
}

pub fn init(allocator: std.mem.Allocator, dtRoot: *const dt.DeviceTreeNode) !void {
    const physicalRegions = try parseMemoryRegions(allocator, dtRoot);
    const reservedRegions = try parseReservedMemoryRegions(allocator, dtRoot);

    kio.log("physical memory regions:", .{});
    for (physicalRegions.items) |reg| {
        const range = reg.range;
        const end = range.addr + range.size - 1;
        kio.log("    mem [0x{x:0>16}-0x{x:0>16}] (size: 0x{x})", .{ range.addr, end, range.size });
    }

    kio.log("reserved memory regions:", .{});
    for (reservedRegions.items) |reg| {
        const range = reg.range;
        const end = range.addr + range.size - 1;
        const noMapString = if (reg.noMap) "no-map" else "map";
        const reusable = if (reg.reusable) "reusable" else "non-reusable";
        kio.log("    {s} [0x{x:0>16}-0x{x:0>16}] (size: 0x{x}) {s} {s}", .{ reg.name, range.addr, end, range.size, noMapString, reusable });
    }
}
