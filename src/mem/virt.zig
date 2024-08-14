const mm = @import("mm.zig");

pub fn map(root: mm.PageTable, virt: mm.VirtualAddress, phys: mm.PhysicalAddress, flags: mm.PageFlags) !void {
    _ = root;
    _ = virt;
    _ = phys;
    _ = flags;
}
