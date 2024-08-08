const mm = @import("mm.zig");

pub const EntriesPerPageTable = 512;

pub const PageFlags = packed struct(u5) {
    readable: bool,
    writable: bool,
    executable: bool,
    user: bool,
    global: bool,
};

const PageTableEntry = packed struct(u64) {
    valid: bool,
    flags: PageFlags,
    accessed: bool,
    dirty: bool,
    __reserved: u2,
    pageNumber0: u9,
    pageNumber1: u9,
    pageNumber2: u9,
};

pub const PageTable = struct {
    entries: *[EntriesPerPageTable]PageTableEntry,

    const Self = @This();

    pub fn fromAddress(virtAddr: mm.VirtualAddress) PageTable {
        const addr = virtAddr.asInt();
        return .{
            .entries = @ptrFromInt(addr),
        };
    }

    fn writeEntry(self: Self, idx: usize, phys: mm.PhysicalAddress, flags: PageFlags) !void {
        if (idx >= EntriesPerPageTable)
            return error.InvalidIdx;

        const entry = PageTableEntry{
            .valid = true,
            .flags = flags,
            .accessed = false,
            .dirty = false,
            .pageNumber0 = phys.pageNumber0,
            .pageNumber1 = phys.pageNumber1,
            .pageNumber2 = phys.pageNumber2,
            .__reserved = 0,
        };

        self.entries[idx] = entry;
    }
};

pub fn map(root: mm.PageTable, virt: mm.VirtualAddress, phys: mm.PhysicalAddress, flags: mm.PageFlags) !void {
    _ = root;
    _ = virt;
    _ = phys;
    _ = flags;
}
