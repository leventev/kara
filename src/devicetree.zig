// documentation: https://github.com/devicetree-org/devicetree-specification

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

const TokenType = enum(u32) {
    beginNode = 1,
    endNode = 2,
    property = 3,
    nop = 4,
    end = 9,
};

const DeviceTreeBlobMagic = 0xD00DFEED;

const bigToNative = std.mem.bigToNative;

fn getString(blob: [*]u32, offset: u32) [*:0]const u8 {
    const stringBlockOffset = bigToNative(u32, blob[dtStringsOffsetIdx]);
    const stringBlockStart = @as([*]u8, @ptrCast(blob)) + @as(usize, stringBlockOffset);
    return @ptrCast(stringBlockStart + @as(usize, offset));
}

fn readToken(tok: u32) TokenType {
    const tokenVal = bigToNative(u32, tok);
    return @enumFromInt(tokenVal);
}

fn readBeginNode(ptr: [*]u32) []const u8 {
    const nodeNamePtr: [*:0]const u8 = @ptrCast(ptr);
    const nodeName: []const u8 = std.mem.span(nodeNamePtr);
    return nodeName;
}

pub const DeviceTreeNode = struct {
    properties: std.StringArrayHashMapUnmanaged([]const u8),
    children: std.StringArrayHashMapUnmanaged(DeviceTreeNode),

    const Self = @This();

    pub fn getProperty(self: Self, name: []const u8) ?[]const u8 {
        return self.properties.get(name);
    }

    pub fn getPropertyU32(self: Self, name: []const u8) ?u32 {
        const prop = self.getProperty(name) orelse return null;
        if (prop.len != @sizeOf(u32))
            return null;

        const u32Ptr: *const u32 = @ptrCast(@alignCast(prop.ptr));
        return bigToNative(u32, u32Ptr.*);
    }

    pub fn getChild(self: Self, name: []const u8) ?*const DeviceTreeNode {
        return self.children.getPtr(name);
    }
};

const NodeProperty = struct { name: []const u8, value: []const u8 };
fn readProperty(blob: [*]u32, ptr: [*]u32) NodeProperty {
    const valueLen = bigToNative(u32, ptr[propValueLenIdx]);
    const nameOffset = bigToNative(u32, ptr[propNameOffsetIdx]);

    const name = getString(blob, nameOffset);
    const value = @as([*]const u8, @ptrCast(&ptr[propValueIdx]))[0..valueLen];

    return NodeProperty{
        .name = std.mem.span(name),
        .value = value,
    };
}

fn ceilDiv(comptime T: type, a: T, b: T) T {
    var val = a / b;
    if (a % b != 0)
        val += 1;
    return val;
}

const DeviceTreeNodeRead = struct { node: DeviceTreeNode, ptrForward: usize };
fn readNode(allocator: std.mem.Allocator, blob: [*]u32, ptr: [*]u32) !DeviceTreeNodeRead {
    var ptrIdx: usize = 0;
    var continueReading = true;

    // NOTE: we do not need to errdefer deallocate the allocated memory
    // since if we can't parse the device tree the kernel should halt thus
    // freeing the memory is redundant
    var properties = try std.StringArrayHashMapUnmanaged([]const u8).init(allocator, &.{}, &.{});
    var children = try std.StringArrayHashMapUnmanaged(DeviceTreeNode).init(allocator, &.{}, &.{});

    while (continueReading) {
        const tokenType: TokenType = readToken(ptr[ptrIdx]);
        ptrIdx += 1;
        switch (tokenType) {
            .beginNode => {
                const name = readBeginNode(ptr + ptrIdx);
                ptrIdx += ceilDiv(usize, name.len + 1, @sizeOf(u32));

                const read = try readNode(allocator, blob, ptr + ptrIdx);
                ptrIdx += read.ptrForward;

                try children.put(allocator, name, read.node);
            },
            .property => {
                const prop = readProperty(blob, ptr + ptrIdx);
                ptrIdx += 2 + ceilDiv(usize, prop.value.len, @sizeOf(u32));

                try properties.put(allocator, prop.name, prop.value);
            },
            .nop => {},
            .end, .endNode => continueReading = false,
        }
    }

    return DeviceTreeNodeRead{
        .node = DeviceTreeNode{
            .children = children,
            .properties = properties,
        },
        .ptrForward = ptrIdx,
    };
}

pub fn printDeviceTree(path: []const u8, node: *const DeviceTreeNode, depth: usize) void {
    const spaceCount = depth * 4;
    var buf: [256]u8 = undefined;
    for (0..spaceCount) |i| {
        buf[i] = ' ';
    }

    kio.log("{s}{s}:", .{ buf[0..spaceCount], path });

    var prop_it = node.properties.iterator();
    while (prop_it.next()) |prop| {
        kio.log("{s}{s} = {any}", .{ buf[0..spaceCount], prop.key_ptr.*, prop.value_ptr.* });
    }

    var child_it = node.children.iterator();
    while (child_it.next()) |child| {
        printDeviceTree(child.key_ptr.*, child.value_ptr, depth + 1);
    }
}

pub const DeviceTreeRoot = struct { node: DeviceTreeNode, addr: usize, size: usize };
pub fn readDeviceTreeBlob(allocator: std.mem.Allocator, blobPtr: *void) !DeviceTreeRoot {
    const blob: [*]u32 = @ptrCast(@alignCast(blobPtr));
    const magic = bigToNative(u32, blob[blobMagicIdx]);
    if (magic != DeviceTreeBlobMagic) {
        return error.MagicMismatch;
    }

    const structBlockOffset = bigToNative(u32, blob[dtStructsOffsetIdx]);
    const structBlockStart = @as([*]u8, @ptrCast(blob)) + @as(usize, structBlockOffset);

    const tokenPtr: [*]u32 = @ptrCast(@alignCast(structBlockStart));
    const tokenType = readToken(tokenPtr[0]);
    if (tokenType != .beginNode)
        return error.InvalidDeviceTree;

    // name should be empty but we don't need to check
    const name = readBeginNode(tokenPtr + 1);

    const ptr = tokenPtr + 1 + ceilDiv(usize, name.len + 1, @sizeOf(u32));
    const rootNodeRead = try readNode(allocator, blob, ptr);
    const rootNode = rootNodeRead.node;
    return DeviceTreeRoot{
        .addr = @intFromPtr(blobPtr),
        .node = rootNode,
        .size = bigToNative(u32, blob[totalSizeIdx]),
    };
}
