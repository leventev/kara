const std = @import("std");
const mm = @import("../../mem/mm.zig");
const kio = @import("../../kio.zig");

pub const EntriesPerPageTable = 512;

// TODO: other arches
pub const SATP = packed struct(u64) {
    physicalPageNumber: u44,
    addresssSpaceID: u16,
    mode: Mode,

    pub const Mode = enum(u4) {
        Bare = 0,
        Sv39 = 8,
        Sv48 = 9,
        Sv57 = 10,
        Sv64 = 11,
    };
};

pub const PageEntryType = enum {
    branch,
    leaf4K,
    leaf2M,
    leaf1G,
};

pub const PageTableEntry = packed struct(u64) {
    valid: bool,
    flags: Flags,
    accessed: bool,
    dirty: bool,
    __reserved: u2,
    pageNumber0: u9,
    pageNumber1: u9,
    pageNumber2: u9,
    __reserved2: u27,

    pub const Flags = packed struct(u5) {
        readable: bool,
        writable: bool,
        executable: bool,
        user: bool,
        global: bool,
    };
};

// TODO: support other addressing modes like Sv48, Sv57...
pub const Sv39PhysicalAddress = packed struct(u64) {
    offset: u12,
    pageNumber0: u9,
    pageNumber1: u9,
    pageNumber2: u9,
    __unused: u25,

    const Self = @This();

    pub inline fn make(addr: u64) Self {
        return @bitCast(addr);
    }

    pub inline fn asInt(self: Self) u64 {
        return @bitCast(self);
    }

    pub inline fn isPageAligned(self: Self) bool {
        return self.offset == 0;
    }
};

pub const Sv39VirtualAddress = packed struct(u64) {
    offset: u12,
    pageNumber0: u9,
    pageNumber1: u9,
    pageNumber2: u9,
    __unused: u25,

    const Self = @This();

    pub inline fn make(addr: u64) Self {
        return @bitCast(addr);
    }

    pub inline fn asInt(self: Self) u64 {
        return @bitCast(self);
    }

    pub inline fn isPageAligned(self: Self) bool {
        return self.offset == 0;
    }
};

pub const PageTable = struct {
    entries: *[EntriesPerPageTable]PageTableEntry,

    const Self = @This();

    // this function is inline since we need to use it before paging is enabled
    // and it's small
    pub inline fn fromAddress(addr: u64) PageTable {
        return .{
            .entries = @ptrFromInt(addr),
        };
    }

    // inline for the same reason as fromAddress
    pub inline fn writeEntry(
        self: *Self,
        idx: usize,
        phys: Sv39PhysicalAddress,
        entryType: PageEntryType,
        flags: PageTableEntry.Flags,
    ) !void {
        if (idx >= EntriesPerPageTable)
            return error.InvalidIdx;

        if (!phys.isPageAligned())
            return error.InvalidAddress;

        _ = switch (entryType) {
            PageEntryType.leaf2M => if (phys.pageNumber0 != 0)
                return error.InvalidAddress,
            PageEntryType.leaf1G => if (phys.pageNumber0 != 0 or phys.pageNumber1 != 0)
                return error.InvalidAddress,
            PageEntryType.branch => if (flags.executable or flags.readable or flags.writable)
                return error.InvalidFlags,
            else => {},
        };

        self.entries[idx] = PageTableEntry{
            .valid = true,
            .flags = flags,
            .accessed = false,
            .dirty = false,
            .pageNumber0 = phys.pageNumber0,
            .pageNumber1 = phys.pageNumber1,
            .pageNumber2 = phys.pageNumber2,
            .__reserved = 0,
            .__reserved2 = 0,
        };
    }

    // inline for the same reason as fromAddress
    pub inline fn zeroEntry(self: *Self, idx: usize) !void {
        if (idx >= EntriesPerPageTable)
            return error.InvalidIdx;

        self.entries[idx] = PageTableEntry{
            .valid = false,
            .flags = PageTableEntry.Flags{
                .executable = false,
                .writable = false,
                .readable = false,
                .global = false,
                .user = false,
            },
            .accessed = false,
            .dirty = false,
            .pageNumber0 = 0,
            .pageNumber1 = 0,
            .pageNumber2 = 0,
            .__reserved = 0,
            .__reserved2 = 0,
        };
    }
};

var rootPageTable: [EntriesPerPageTable]PageTableEntry align(4096) linksection(".bss") = undefined;
//var kernelspacePageTable: [EntriesPerPageTable]mm.PageTableEntry align(4096) linksection(".bss") = undefined;

fn writeSATP(satp: SATP) void {
    const val: u64 = @bitCast(satp);
    asm volatile ("csrw satp, %[satp]"
        :
        : [satp] "r" (val),
    );
}

pub fn setupPaging() void {
    // since rootPageTable is in .bss it should be all zeros
    var pageTable = PageTable.fromAddress(@intFromPtr(&rootPageTable));

    const KernelRegionStart = 0x80000000;
    const KernelRegionSize = 0x40000000;
    const KernelRegionEnd = KernelRegionStart + KernelRegionSize;

    const DirectMappingStart = 0xffffffc000000000;
    const DirectMappingSize = 128 * 0x40000000;
    const DirectMappingEnd = DirectMappingStart + DirectMappingSize;

    // unfortunately llvm does not support -mcmodel=large yet so we have to identity map the kernel for now
    // TODO: map the kernel high
    // TODO: map smaller pages and set correct flags
    pageTable.writeEntry(
        2,
        Sv39PhysicalAddress.make(KernelRegionStart),
        PageEntryType.leaf1G,
        PageTableEntry.Flags{
            .executable = true,
            .readable = true,
            .writable = true,
            .global = true,
            .user = false,
        },
    ) catch unreachable;

    // map 128GiB directly
    for (256..256 + 128, 0..) |i, j| {
        const physAddr = Sv39PhysicalAddress.make(j * (1024 * 1024 * 1024));
        pageTable.writeEntry(
            i,
            physAddr,
            PageEntryType.leaf1G,
            PageTableEntry.Flags{
                .executable = false,
                .readable = true,
                .writable = true,
                .user = false,
                .global = true,
            },
        ) catch unreachable;
    }

    const pageTablePhys = @intFromPtr(&rootPageTable);
    const pageNumber: u44 = @intCast(std.math.shr(u64, pageTablePhys, 12));
    const satp = SATP{
        .mode = SATP.Mode.Sv39,
        .addresssSpaceID = 0,
        .physicalPageNumber = pageNumber,
    };

    writeSATP(satp);

    kio.info("Virtual memory map:", .{});
    kio.info("    Kernel: [0x{x:0>16}-0x{x:0>16}] ({} KiB)", .{
        KernelRegionStart,
        KernelRegionEnd,
        KernelRegionSize / 1024,
    });
    kio.info("      HHDM: [0x{x:0>16}-0x{x:0>16}] ({} KiB)", .{
        DirectMappingStart,
        DirectMappingEnd,
        DirectMappingSize / 1024,
    });
}
