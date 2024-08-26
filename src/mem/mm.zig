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

pub const PageSize = 4096;
pub const FrameSize = PageSize;

pub const EntriesPerPageTable = 512;

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
    noMap: bool,
    reusable: bool,
    system: bool,
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

fn readMemoryPair(buff: []const u8, idx: usize, entrySize: usize) MemoryRegion {
    const entryBase = idx * entrySize;
    const entry = buff[entryBase .. entryBase + entrySize];

    const addr = std.mem.readInt(u64, entry[0..8], .big);
    const size = std.mem.readInt(u64, entry[8..16], .big);

    return MemoryRegion{ .start = addr, .size = size };
}

fn parseMemoryRegions(
    allocator: std.mem.Allocator,
    dtRoot: *const dt.DeviceTreeNode,
) !std.ArrayListUnmanaged(PhysicalMemoryRegion) {
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

fn parseReservedMemoryRegions(
    allocator: std.mem.Allocator,
    dtRoot: *const dt.DeviceTreeNode,
) !std.ArrayListUnmanaged(ReservedMemoryRegion) {
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
                .system = false,
            });
        }
    }

    return regions;
}

const MinimumRegionSize = 8 * 4096;

fn processRegion(
    regs: *std.ArrayList(MemoryRegion),
    region: PhysicalMemoryRegion,
    reservedRegions: []const ReservedMemoryRegion,
) !void {
    std.debug.assert(region.range.start % PageSize == 0);
    std.debug.assert(region.range.size % PageSize == 0);

    var range = region.range;

    for (reservedRegions) |resv| {
        std.debug.assert(resv.range.start % PageSize == 0);
        std.debug.assert(resv.range.size % PageSize == 0);

        if (!range.intersects(resv.range))
            continue;

        const resvRange = resv.range;

        const end = range.end();
        const resvEnd = resvRange.end();

        // the reserved region starts before or at the same address as the physical region
        if (resvRange.start <= region.range.start) {
            // cut off the interescting part at the beginning of the region
            range.start = resvEnd;
            range.size = end - range.start;

            continue;
        }

        // the reserved region ends after or at the same address as the physical region
        if (resvEnd >= end) {
            // cut off the interescting part at the end of the region
            range.size = resvRange.start - range.start;

            continue;
        }

        // the reserved region is inside the physical region
        range.size = resvRange.start - range.start;

        // do the same process for the region on the right side of the reserved region
        const otherRegion = PhysicalMemoryRegion{
            .range = MemoryRegion{
                .start = resvEnd,
                .size = end - resvEnd,
            },
        };

        try processRegion(regs, otherRegion, reservedRegions);
    }

    if (range.size >= MinimumRegionSize)
        try regs.append(range);
}

fn getUsableRegions(
    allocator: std.mem.Allocator,
    physicalRegions: []const PhysicalMemoryRegion,
    reservedRegions: []const ReservedMemoryRegion,
) !std.ArrayList(MemoryRegion) {
    var regions = std.ArrayList(MemoryRegion).init(allocator);

    for (physicalRegions) |phys| {
        try processRegion(&regions, phys, reservedRegions);
    }

    return regions;
}

fn addKernelReservedMemory(
    allocator: std.mem.Allocator,
    reservedRegions: *std.ArrayListUnmanaged(ReservedMemoryRegion),
) !void {
    // we can(have to) align forward the end address of the segments because the next segment should be at the next possible 4K aligned address
    const textStart = @intFromPtr(&__text_start);
    const textEnd = @intFromPtr(&__text_end);
    const textSize = textEnd - textStart;

    const dataStart = @intFromPtr(&__data_start);
    const dataEnd = @intFromPtr(&__data_end);
    const dataSize = dataEnd - dataStart;

    const rodataStart = @intFromPtr(&__rodata_start);
    const rodataEnd = @intFromPtr(&__rodata_end);
    const rodataSize = rodataEnd - rodataStart;

    const bssStart = @intFromPtr(&__bss_start);
    const bssEnd = @intFromPtr(&__bss_end);
    const bssSize = bssEnd - bssStart;

    const stackStart = @intFromPtr(&__stack_start);
    const stackEnd = @intFromPtr(&__stack_end);
    const stackSize = stackEnd - stackStart;

    const kernelStart = @intFromPtr(&__kernel_start);
    // we align forward so that the size of the region is divisible by 4K
    const kernelEnd = std.mem.alignForward(usize, @intFromPtr(&__kernel_end), 4096);
    const kernelSize = kernelEnd - kernelStart;

    kio.log("Kernel code: {} KiB, rodata: {} KiB, data: {} KiB, bss: {} KiB, stack: {} KiB", .{
        textSize / 1024,
        rodataSize / 1024,
        dataSize / 1024,
        bssSize / 1024,
        stackSize / 1024,
    });

    try reservedRegions.append(allocator, ReservedMemoryRegion{
        .name = "kernel",
        .noMap = true,
        .reusable = false,
        .system = true,
        .range = MemoryRegion{
            .start = kernelStart,
            .size = kernelSize,
        },
    });
}

fn addDeviceTreeReservedMemory(
    allocator: std.mem.Allocator,
    reservedRegions: *std.ArrayListUnmanaged(ReservedMemoryRegion),
    dtRoot: *const dt.DeviceTreeRoot,
) !void {
    // we need to reserve memory for the DT itself
    const dtStart = std.mem.alignBackward(u64, @intCast(dtRoot.addr), 4096);
    const dtEnd = std.mem.alignForward(u64, @intCast(dtRoot.addr + dtRoot.size), 4096);

    const dtRegion = ReservedMemoryRegion{
        .name = "device-tree",
        .noMap = true,
        .reusable = false,
        .system = false,
        .range = MemoryRegion{
            .start = dtStart,
            .size = dtEnd - dtStart,
        },
    };
    try reservedRegions.append(allocator, dtRegion);
}

fn printPhysicalRegions(physicalRegions: []const PhysicalMemoryRegion) void {
    kio.log("Physical memory regions:", .{});
    for (physicalRegions) |reg| {
        const range = reg.range;
        const sizeInKiB = range.size / 1024;
        kio.log(
            "    [0x{x:0>16}-0x{x:0>16}] ({} KiB)",
            .{ range.start, range.end() - 1, sizeInKiB },
        );
    }
}

fn printReservedRegions(reservedRegions: []const ReservedMemoryRegion) void {
    kio.log("Reserved memory regions:", .{});
    for (reservedRegions) |reg| {
        const range = reg.range;
        const sizeInKiB = range.size / 1024;
        if (reg.system) {
            kio.log("    [0x{x:0>16}-0x{x:0>16}] <{s}> ({} KiB) system", .{
                range.start,
                range.end() - 1,
                reg.name,
                sizeInKiB,
            });
        } else {
            const noMapString = if (reg.noMap) "no-map" else "map";
            const reusableString = if (reg.reusable) "reusable" else "non-reusable";
            kio.log("    [0x{x:0>16}-0x{x:0>16}] <{s}> ({} KiB) {s} {s}", .{
                range.start,
                range.end() - 1,
                reg.name,
                sizeInKiB,
                noMapString,
                reusableString,
            });
        }
    }
}

fn printUsableRegions(regions: []const MemoryRegion) void {
    kio.log("Usable memory regions:", .{});
    for (regions) |reg| {
        const sizeInKiB = reg.size / 1024;
        kio.log(
            "    [0x{x:0>16}-0x{x:0>16}] ({} KiB)",
            .{ reg.start, reg.end() - 1, sizeInKiB },
        );
    }
}

pub fn getFrameRegions(allocator: std.mem.Allocator, dtRoot: *const dt.DeviceTreeRoot) ![]const MemoryRegion {
    var physicalRegions = try parseMemoryRegions(allocator, &dtRoot.node);
    defer physicalRegions.deinit(allocator);

    var reservedRegions = try parseReservedMemoryRegions(allocator, &dtRoot.node);
    defer reservedRegions.deinit(allocator);

    try addDeviceTreeReservedMemory(allocator, &reservedRegions, dtRoot);
    try addKernelReservedMemory(allocator, &reservedRegions);

    printPhysicalRegions(physicalRegions.items);
    printReservedRegions(reservedRegions.items);

    var usableRegions = try getUsableRegions(
        allocator,
        physicalRegions.items,
        reservedRegions.items,
    );

    printUsableRegions(usableRegions.items);

    return usableRegions.toOwnedSlice();
}

const HHDMStart = 0xffffffc000000000;

pub fn physicalToHHDMAddress(phys: PhysicalAddress) VirtualAddress {
    return VirtualAddress.make(0xffffffc000000000 + phys.asInt());
}
