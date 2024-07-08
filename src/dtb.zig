const kio = @import("kio.zig");
const std = @import("std");

const DeviceTreeBlob = struct {
    magic: u32,
    totalSize: u32,
    dtStructOffset: u32,
    dtStringsOffset: u32,
    memRsvmapOff: u32,
    version: u32,
    lastCompatibleVersion: u32,
    bootCpuIDPhys: u32,
    dtStringsSize: u32,
    dtStructsSize: u32,
};

const DeviceTreeReserveEntry = struct {
    address: u64,
    size: u64,
};

const DeviceTreeBlobMagic = 0xD00DFEED;

fn readMemReserveEntries(blob: *DeviceTreeBlob) void {
    const memRsvmapOff = std.mem.bigToNative(u32, blob.memRsvmapOff);
    const listStart = @as([*]u8, @ptrCast(blob)) + @as(usize, memRsvmapOff);
    const entries: [*]DeviceTreeReserveEntry = @ptrCast(@alignCast(listStart));

    var i: usize = 0;
    while (entries[i].address != 0 and entries[i].size != 0) : (i += 1) {
        const addr = std.mem.bigToNative(u64, entries[i].address);
        const size = std.mem.bigToNative(u64, entries[i].size);

        kio.log("addr: {x} size: {} region: {x}-{x}", .{ addr, size, addr, addr + size });
    }
}

pub fn readDeviceTreeBlob(ptr: *void) !void {
    const blob: *DeviceTreeBlob = @ptrCast(@alignCast(ptr));
    const magic = std.mem.bigToNative(u32, blob.magic);
    if (magic != DeviceTreeBlobMagic) {
        return error.MagicMismatch;
    }

    const totalSize = std.mem.bigToNative(u32, blob.totalSize);
    const memRsvmapOff = std.mem.bigToNative(u32, blob.memRsvmapOff);
    kio.log("magic: {x} totalSize: {} memRvsmapOff: {x}", .{ magic, totalSize, memRsvmapOff });
    readMemReserveEntries(blob);
}
