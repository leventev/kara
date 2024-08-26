// documentation: https://github.com/devicetree-org/devicetree-specification

const kio = @import("kio.zig");
const std = @import("std");

const blob_magic_idx = 0x0;
const total_size_idx = 0x1;
const dt_structs_offset_idx = 0x2;
const dt_strings_offset_idx = 0x3;
const mem_rsvmap_offset_idx = 0x4;
const version_idx = 0x5;
const last_compatible_version_idx = 0x6;
const boot_cpu_id_phys_idx = 0x7;
const dt_strings_size_idx = 0x8;
const dt_structs_size_idx = 0x9;

const prop_value_len_idx = 0x0;
const prop_name_offset_idx = 0x1;
const prop_value_idx = 0x2;

const TokenType = enum(u32) {
    begin_node = 1,
    end_node = 2,
    property = 3,
    nop = 4,
    end = 9,
};

const device_tree_blob_magic = 0xD00DFEED;

const bigToNative = std.mem.bigToNative;

fn getString(blob: [*]u32, offset: u32) [*:0]const u8 {
    const string_block_offset = bigToNative(u32, blob[dt_strings_offset_idx]);
    const string_block_start = @as([*]u8, @ptrCast(blob)) + @as(usize, string_block_offset);
    return @ptrCast(string_block_start + @as(usize, offset));
}

fn readToken(tok: u32) TokenType {
    const token_val = bigToNative(u32, tok);
    return @enumFromInt(token_val);
}

fn readBeginNode(ptr: [*]u32) []const u8 {
    const node_name_ptr: [*:0]const u8 = @ptrCast(ptr);
    const node_name: []const u8 = std.mem.span(node_name_ptr);
    return node_name;
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
    const value_len = bigToNative(u32, ptr[prop_value_len_idx]);
    const name_offset = bigToNative(u32, ptr[prop_name_offset_idx]);

    const name = getString(blob, name_offset);
    const value = @as([*]const u8, @ptrCast(&ptr[prop_value_idx]))[0..value_len];

    return NodeProperty{
        .name = std.mem.span(name),
        .value = value,
    };
}

const DeviceTreeNodeRead = struct { node: DeviceTreeNode, ptrForward: usize };
fn readNode(allocator: std.mem.Allocator, blob: [*]u32, ptr: [*]u32) !DeviceTreeNodeRead {
    var ptr_idx: usize = 0;
    var continue_reading = true;

    // NOTE: we do not need to errdefer deallocate the allocated memory
    // since if we can't parse the device tree the kernel should halt thus
    // freeing the memory is redundant
    var properties = try std.StringArrayHashMapUnmanaged([]const u8).init(allocator, &.{}, &.{});
    var children = try std.StringArrayHashMapUnmanaged(DeviceTreeNode).init(allocator, &.{}, &.{});

    while (continue_reading) {
        const tokenType: TokenType = readToken(ptr[ptr_idx]);
        ptr_idx += 1;
        switch (tokenType) {
            .begin_node => {
                const name = readBeginNode(ptr + ptr_idx);
                ptr_idx += std.math.divCeil(usize, name.len + 1, @sizeOf(u32)) catch unreachable;

                const read = try readNode(allocator, blob, ptr + ptr_idx);
                ptr_idx += read.ptrForward;

                try children.put(allocator, name, read.node);
            },
            .property => {
                const prop = readProperty(blob, ptr + ptr_idx);
                const words = std.math.divCeil(usize, prop.value.len, @sizeOf(u32)) catch unreachable;
                ptr_idx += 2 + words;

                try properties.put(allocator, prop.name, prop.value);
            },
            .nop => {},
            .end, .end_node => continue_reading = false,
        }
    }

    return DeviceTreeNodeRead{
        .node = DeviceTreeNode{
            .children = children,
            .properties = properties,
        },
        .ptrForward = ptr_idx,
    };
}

pub fn printDeviceTree(path: []const u8, node: *const DeviceTreeNode, depth: usize) void {
    const space_count = depth * 4;
    var buf: [256]u8 = undefined;
    for (0..space_count) |i| {
        buf[i] = ' ';
    }

    kio.info("{s}{s}:", .{ buf[0..space_count], path });

    var prop_it = node.properties.iterator();
    while (prop_it.next()) |prop| {
        kio.info("{s}{s} = {any}", .{ buf[0..space_count], prop.key_ptr.*, prop.value_ptr.* });
    }

    var child_it = node.children.iterator();
    while (child_it.next()) |child| {
        printDeviceTree(child.key_ptr.*, child.value_ptr, depth + 1);
    }
}

pub const DeviceTreeRoot = struct { node: DeviceTreeNode, addr: usize, size: usize };
pub fn readDeviceTreeBlob(allocator: std.mem.Allocator, blobPtr: *void) !DeviceTreeRoot {
    const blob: [*]u32 = @ptrCast(@alignCast(blobPtr));
    const magic = bigToNative(u32, blob[blob_magic_idx]);
    if (magic != device_tree_blob_magic) {
        return error.MagicMismatch;
    }

    const struct_block_offset = bigToNative(u32, blob[dt_structs_offset_idx]);
    const struct_block_start = @as([*]u8, @ptrCast(blob)) + @as(usize, struct_block_offset);

    const token_ptr: [*]u32 = @ptrCast(@alignCast(struct_block_start));
    const token_type = readToken(token_ptr[0]);
    if (token_type != .begin_node)
        return error.InvalidDeviceTree;

    // name should be empty but we don't need to check
    const name = readBeginNode(token_ptr + 1);

    const words = std.math.divCeil(usize, name.len + 1, @sizeOf(u32)) catch unreachable;
    const ptr = token_ptr + 1 + words;
    const root_node_read = try readNode(allocator, blob, ptr);
    const root_node = root_node_read.node;
    return DeviceTreeRoot{
        .addr = @intFromPtr(blobPtr),
        .node = root_node,
        .size = bigToNative(u32, blob[total_size_idx]),
    };
}
