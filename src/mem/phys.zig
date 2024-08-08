const mm = @import("mm.zig");
const std = @import("std");
const kio = @import("../kio.zig");

const LineType = u64;
const FramesPerLine = @bitSizeOf(LineType);
const BitmapLineFull = std.math.maxInt(LineType);

const PageFrameRegion = struct {
    address: mm.PhysicalAddress,
    totalFrameCount: usize,
    freeFrameCount: usize,
    bitmap: []LineType,
    firstFreeLineIdx: usize,

    const Self = @This();

    fn full(self: Self) bool {
        return self.freeFrameCount == 0;
    }

    fn alloc(self: *Self) mm.PhysicalAddress {
        if (self.full())
            @panic("Trying to allocate from frame region with no free frames available");

        // NOTE: we could store the frame index instead of just the bitmap index
        // but that would introduce an extra if statement and i believe it's prettier this way :)
        for (self.firstFreeLineIdx..self.bitmap.len) |lineIdx| {
            const line = self.bitmap[lineIdx];
            if (line == BitmapLineFull)
                continue;

            for (0..FramesPerLine) |bitIdx| {
                const bit: LineType = std.math.shl(LineType, 1, bitIdx);
                const allocated = line & bit > 0;
                if (allocated)
                    continue;

                self.firstFreeLineIdx = lineIdx;
                self.bitmap[lineIdx] |= bit;
                self.freeFrameCount -= 1;

                const address = self.address.asInt() + (lineIdx * FramesPerLine + bitIdx) * mm.FrameSize;
                return mm.PhysicalAddress.make(address);
            }
        }

        @panic("Can not find a free frame but freeFrameCount != 0");
    }

    fn free(self: *Self, addr: mm.PhysicalAddress) void {
        const address = addr.asInt() - self.address.asInt();
        const lineIdx = address / FramesPerLine;
        const bitIdx = address % FramesPerLine;

        const bit = std.math.shl(LineType, 1, bitIdx);

        self.bitmap[lineIdx] &= ~bit;
        self.freeFrameCount += 1;
    }

    fn contains(self: Self, addr: mm.PhysicalAddress) bool {
        const address = addr.asInt();
        const thisAddress = self.address.asInt();

        if (address < thisAddress) return false;
        const relativeAddr = address - thisAddress;
        const frameIndex = relativeAddr / mm.FrameSize;

        return frameIndex < self.totalFrameCount;
    }
};

// TODO: thread safety
const PhysicalFrameAllocator = struct {
    regions: []PageFrameRegion,
    totalFrameCount: usize,
    freeFrameCount: usize,

    const Self = @This();

    fn alloc(self: *Self) !mm.PhysicalAddress {
        if (self.full())
            return error.OutOfMemory;

        for (self.regions) |*region| {
            if (region.full())
                continue;

            const addr = region.alloc();
            self.freeFrameCount -= 1;
            return addr;
        }

        @panic("Can not find a free frame but freeFrameCount != 0");
    }

    fn free(self: *Self, addr: mm.PhysicalAddress) void {
        if (!addr.isPageAligned())
            @panic("Address is not page aligned");

        for (self.regions) |*region| {
            if (!region.contains(addr))
                continue;

            region.free(addr);
            self.freeFrameCount += 1;
            return;
        }

        @panic("Invalid address");
    }

    fn full(self: Self) bool {
        return self.freeFrameCount == 0;
    }
};

var FrameAllocator: PhysicalFrameAllocator = undefined;

pub fn init(allocator: std.mem.Allocator, regions: []const mm.MemoryRegion) !void {
    // TODO: do some kind of magic so we don't depend on the temporary allocator

    var regs = try allocator.alloc(PageFrameRegion, regions.len);

    var totalFrames: usize = 0;
    var totalLines: usize = 0;

    for (regions, 0..) |physReg, i| {
        const address = mm.PhysicalAddress.make(physReg.start);
        const frameCount: usize = physReg.size / mm.FrameSize;
        const linesRequired = std.math.divCeil(usize, frameCount, FramesPerLine) catch unreachable;

        const bitmap = try allocator.alloc(LineType, linesRequired);
        @memset(bitmap, 0);

        totalFrames += frameCount;
        totalLines += linesRequired;

        regs[i] = PageFrameRegion{
            .address = address,
            .totalFrameCount = frameCount,
            .freeFrameCount = frameCount,
            .bitmap = bitmap,
            .firstFreeLineIdx = 0,
        };
    }

    FrameAllocator = PhysicalFrameAllocator{
        .regions = regs,
        .totalFrameCount = totalFrames,
        .freeFrameCount = totalFrames,
    };

    kio.log("Physical frame allocator initialized with {} frames ({} KiB) available", .{
        totalFrames,
        totalFrames * 4,
    });
    kio.log("{} bytes allocated for bitmaps", .{@sizeOf(LineType) * totalLines});
}

pub fn alloc() !mm.PhysicalAddress {
    return FrameAllocator.alloc();
}

pub fn free(addr: mm.PhysicalAddress) void {
    FrameAllocator.free(addr);
}
