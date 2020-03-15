const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const StructureOfArrays = @import("structure_of_arrays.zig").StructureOfArrays;

fn alignPointerOffset(comptime Type: type, p: [*]u8) usize {
    return std.mem.alignForward(@ptrToInt(p), @alignOf(Type)) - @ptrToInt(p);
}

pub fn NodeKeyValueStorage(comptime Node: type, comptime Key: type, comptime Value: type) type {
    return struct{
        soa: SoAType,
        const SoAType = StructureOfArrays(struct {node: Node, key: Key, value: Value,});

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return .{.soa=SoAType.init(allocator)};
        }

        pub fn deinit(self: *Self) void {
            self.soa.deinit();
        }

        pub fn empty(self: Self) bool {
            return self.soa.empty();
        }

        pub fn size(self: Self) usize {
            return self.soa.size();
        }

        pub fn capacity(self: Self) usize {
            return self.soa.capacity();
        }

        pub fn clear(self: *Self) void {
            self.soa.clear();
        }

        pub fn append(self: *Self, node: Node, key: Key, value: Value) !void {
            return self.soa.append(.{.node=node, .key=key, .value=value});
        }

        pub fn growCapacity(self: *Self, amount: usize) !void {
            return self.soa.growCapacity(amount);
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            return self.soa.ensureCapacity(new_capacity);
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            return self.soa.setCapacity(new_capacity);
        }

        pub fn nodes(self: Self) []Node {
            return self.soa.span("node");
        }

        pub fn nodeAt(self: Self, index: usize) Node {
            return self.soa.at("node", index);
        }

        pub fn keys(self: Self) []Key {
            return self.soa.span("key");
        }

        pub fn keyAt(self: Self, index: usize) Key {
            return self.soa.at("key", index);
        }

        pub fn values(self: Self) []Value {
            return self.soa.span("value");
        }

        pub fn valueAt(self: Self, index: usize) Value {
            return self.soa.at("value", index);
        }

        pub fn popBack(self: *Self) void {
            self.soa.popBack();
        }
    };
}

test "NodeKeyValueStorage initialization" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    testing.expect(container.empty());
    testing.expectEqual(container.size(), 0);
    testing.expectEqual(container.capacity(), 0);
}

test "NodeKeyValueStorage append elements" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 1);
    testing.expect(!container.empty());
    testing.expectEqual(container.size(), 1);
    testing.expect(container.capacity() >= 1);

    try container.append(1, 2.0, 3);
    testing.expect(!container.empty());
    testing.expectEqual(container.size(), 2);
    testing.expect(container.capacity() >= 2);
}

test "NodeKeyValueStorage get nodes" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 1);
    try container.append(1, 2.0, 3);
    try container.append(2, 3.0, 4);
    try container.append(3, 4.0, 5);

    testing.expectEqual(container.nodeAt(0), 0);
    testing.expectEqual(container.nodeAt(1), 1);
    testing.expectEqual(container.nodeAt(2), 2);
    testing.expectEqual(container.nodeAt(3), 3);
}

test "NodeKeyValueStorage get keys" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 1);
    try container.append(1, 2.0, 3);
    try container.append(2, 3.0, 4);
    try container.append(3, 4.0, 5);

    testing.expectEqual(container.keyAt(0), 1.0);
    testing.expectEqual(container.keyAt(1), 2.0);
    testing.expectEqual(container.keyAt(2), 3.0);
    testing.expectEqual(container.keyAt(3), 4.0);
}

test "NodeKeyValueStorage get values" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 2);
    try container.append(1, 2.0, 3);
    try container.append(2, 3.0, 4);
    try container.append(3, 4.0, 5);

    testing.expectEqual(container.valueAt(0), 2);
    testing.expectEqual(container.valueAt(1), 3);
    testing.expectEqual(container.valueAt(2), 4);
    testing.expectEqual(container.valueAt(3), 5);
}
