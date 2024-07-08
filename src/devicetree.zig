const kio = @import("kio.zig");
const std = @import("std");

const blobMagicIdx = 0x0;
const totalSizeIdx = 0x1;
const dtStructsOffsetIdx = 0x2;
const dtStringsOffsetIdx = 0x3;
const memRsvmapOffsetIdx = 0x4;
const versionIdx = 0x5;
const lastCompatibleVersionIdx = 0x6;
const bootCpuIDPhyIdx = 0x7;
const dtStringsSizeIdx = 0x8;
const dtStructsSizeIdx = 0x9;

const propValueLenIdx = 0x0;
const propNameOffsetIdx = 0x1;
const propValueIdx = 0x2;

const LexicalTokenType = enum(u32) {
    beginNode = 1,
    endNode = 2,
    property = 3,
    nop = 4,
    end = 9,
};

const DeviceTreeBlobMagic = 0xD00DFEED;

const bigToNative = std.mem.bigToNative;

fn readMemReserveEntries(blob: [*]u32) void {
    const memRsvmapOff = bigToNative(u32, blob[memRsvmapOffsetIdx]);
    const listStart = @as([*]u8, @ptrCast(blob)) + @as(usize, memRsvmapOff);
    const entries: [*]u64 = @ptrCast(@alignCast(listStart));

    var i: usize = 0;
    while (entries[i * 2] != 0 and entries[i * 2 + 1] != 0) : (i += 1) {
        const addr = bigToNative(u64, entries[i * 2]);
        const size = bigToNative(u64, entries[i * 2 + 1]);

        kio.log("addr: {x} size: {} region: {x}-{x}", .{ addr, size, addr, addr + size });
    }
}

fn getString(blob: [*]u32, offset: u32) [*:0]const u8 {
    const stringBlockOffset = bigToNative(u32, blob[dtStringsOffsetIdx]);
    const stringBlockStart = @as([*]u8, @ptrCast(blob)) + @as(usize, stringBlockOffset);
    return @ptrCast(stringBlockStart + @as(usize, offset));
}

fn readLexicalBlocks(blob: [*]u32) void {
    const structBlockOffset = bigToNative(u32, blob[dtStructsOffsetIdx]);
    const structBlockStart = @as([*]u8, @ptrCast(blob)) + @as(usize, structBlockOffset);

    const ptr: [*]u32 = @ptrCast(@alignCast(structBlockStart));
    var ptrIdx: usize = 0;

    var nodeDepth: usize = 0;
    var hasNextToken = true;

    while (hasNextToken) {
        const tokenVal = bigToNative(u32, ptr[ptrIdx]);
        const tokenType: LexicalTokenType = @enumFromInt(tokenVal);
        ptrIdx += 1;
        switch (tokenType) {
            .beginNode => {
                nodeDepth += 1;

                const nodeNamePtr: [*:0]const u8 = @ptrCast(&ptr[ptrIdx]);
                const nodeName: []const u8 = std.mem.span(nodeNamePtr);
                const totalLength = nodeName.len + 1;

                kio.log("name: {s}", .{nodeName});

                // string length and align to 4 bytes
                ptrIdx += totalLength / @sizeOf(u32);
                if (totalLength % @sizeOf(u32) != 0)
                    ptrIdx += 1;
            },
            .property => {
                const valueLen = bigToNative(u32, ptr[ptrIdx + propValueLenIdx]);
                const nameOffset = bigToNative(u32, ptr[ptrIdx + propNameOffsetIdx]);

                const name = getString(blob, nameOffset);
                const value = @as([*]u8, @ptrCast(&ptr[ptrIdx + propValueIdx]))[0..valueLen];
                kio.log("property: {s} {any}", .{ name, value });

                // token struct
                ptrIdx += 2;
                // value length and align to 4 bytes
                ptrIdx += valueLen / @sizeOf(u32);
                if (valueLen % @sizeOf(u32) != 0)
                    ptrIdx += 1;
            },
            .endNode => {
                nodeDepth -= 1;
            },
            .nop => {},
            .end => hasNextToken = false,
        }
    }
}

pub fn readDeviceTreeBlob(ptr: *void) !void {
    const blob: [*]u32 = @ptrCast(@alignCast(ptr));
    const magic = bigToNative(u32, blob[blobMagicIdx]);
    if (magic != DeviceTreeBlobMagic) {
        return error.MagicMismatch;
    }

    readMemReserveEntries(blob);
    readLexicalBlocks(blob);
}
