const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

fn alignPointerOffset(comptime Type: type, p: [*]u8) usize {
    return ((@ptrToInt(p) + @alignOf(Type) - 1) & ~(@as(usize, @alignOf(Type) - 1))) - @ptrToInt(p);
}

pub fn NodeKeyValueStorage(comptime Node: type, comptime Key: type, comptime Value: type) type {
    return struct {
        node_key_value_storage: []align(@alignOf(Node)) u8,
        storage_size: usize,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            //debug.warn("Alignement of storage is {}", usize(@alignOf(Node)));
            return Self{
                .node_key_value_storage = &[_]u8{},
                .storage_size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.node_key_value_storage);
        }

        pub fn empty(self: Self) bool {
            return self.size() == 0;
        }

        pub fn size(self: Self) usize {
            return self.storage_size;
        }

        pub fn capacity(self: Self) usize {
            return self.node_key_value_storage.len / (@sizeOf(Node) + @sizeOf(Key) + @sizeOf(Value));
        }

        pub fn clear(self: *Self) void {
            self.storage_size = 0;
        }

        pub fn append(self: *Self, node: Node, key: Key, value: Value) !void {
            const old_size = self.storage_size;
            const new_size = old_size + 1;
            try self.ensureCapacity(new_size);
            self.storage_size = new_size;
            self.nodes()[old_size] = node;
            self.keys()[old_size] = key;
            self.values()[old_size] = value;
        }

        pub fn growCapacity(self: *Self, amount: usize) !void {
            const old_capacity = self.capacity();
            const new_capacity = old_capacity + std.math.max(old_capacity / 2, amount);
            try self.setCapacity(new_capacity);
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            if (new_capacity > self.capacity()) {
                try self.growCapacity(new_capacity - self.capacity());
            }
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            const old_nodes = self.nodes();
            const old_keys = self.keys();
            const old_values = self.values();
            var old_storage = self.node_key_value_storage;
            const byte_size = new_capacity * (@sizeOf(Node) + @sizeOf(Key) + @sizeOf(Value)) + @alignOf(Key) + @alignOf(Value);
            self.node_key_value_storage = try self.allocator.alignedAlloc(u8, @alignOf(Node), byte_size);
            var new_nodes = self.nodes();
            var new_keys = self.keys();
            var new_values = self.values();
            std.mem.copy(Node, new_nodes, old_nodes);
            std.mem.copy(Key, new_keys, old_keys);
            std.mem.copy(Value, new_values, old_values);
            self.allocator.free(old_storage);
        }

        pub fn nodes(self: Self) []Node {
            return @bytesToSlice(Node, self.node_key_value_storage[0 .. self.storage_size * @sizeOf(Node)]);
        }

        pub fn nodeAt(self: Self, index: usize) Node {
            return self.nodes()[index];
        }

        pub fn keys(self: Self) []Key {
            const start_offset = self.capacity() * @sizeOf(Node);
            const offset = alignPointerOffset(Key, self.node_key_value_storage.ptr + start_offset) + start_offset;
            const key_data_slice = self.node_key_value_storage[offset .. offset + self.capacity() * @sizeOf(Key)];
            return @alignCast(@alignOf(Key), @bytesToSlice(Key, key_data_slice));
        }

        pub fn keyAt(self: Self, index: usize) Key {
            return self.keys()[index];
        }

        pub fn values(self: Self) []Value {
            const start_offset = self.capacity() * (@sizeOf(Node) + @sizeOf(Key)) + (@alignOf(Key) * @as(usize, @boolToInt(!self.empty())));
            const offset = alignPointerOffset(Value, self.node_key_value_storage.ptr + start_offset) + start_offset;
            const value_data_slice = self.node_key_value_storage[offset .. offset + self.capacity() * @sizeOf(Value)];
            return @alignCast(@alignOf(Value), @bytesToSlice(Value, value_data_slice));
        }

        pub fn valueAt(self: Self, index: usize) Value {
            return self.values()[index];
        }

        pub fn popBack(self: *Self) void {
            self.storage_size -= 1;
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

test "NodeKeyValueStorage clear" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 1);
    try container.append(0, 1.0, 1);
    try container.append(0, 1.0, 1);
    testing.expectEqual(container.size(), 3);
    testing.expect(!container.empty());

    container.clear();

    testing.expectEqual(container.size(), 0);
    testing.expect(container.empty());
}

test "NodeKeyValueStorage set capacity" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();
    testing.expectEqual(container.capacity(), 0);
    try container.setCapacity(10);
    testing.expectEqual(container.capacity(), 10);
}

test "NodeKeyValueStorage grow capacity" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();
    testing.expectEqual(container.capacity(), 0);
    try container.growCapacity(1);
    testing.expect(container.capacity() >= 1);
    try container.growCapacity(10);
    testing.expect(container.capacity() >= 10);
    try container.growCapacity(1);
    testing.expect(container.capacity() >= 15);
}

test "NodeKeyValueStorage ensure capacity" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();
    testing.expectEqual(container.capacity(), 0);
    try container.ensureCapacity(10);
    testing.expect(container.capacity() >= 10);
    try container.ensureCapacity(0);
    testing.expect(container.capacity() >= 10);
    try container.ensureCapacity(20);
    testing.expect(container.capacity() >= 20);
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

test "NodeKeyValueStorage don't grow capacity if not needed" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.setCapacity(10);
    testing.expectEqual(container.capacity(), 10);
    try container.append(3, 4.0, 5);
    testing.expectEqual(container.capacity(), 10);
}

test "NodeKeyValueStorage pop back" {
    var container = NodeKeyValueStorage(u32, f64, i128).init(testing.allocator);
    defer container.deinit();

    try container.append(0, 1.0, 2);
    try container.append(1, 2.0, 3);
    try container.append(2, 3.0, 4);
    try container.append(3, 4.0, 5);

    testing.expectEqual(container.size(), 4);
    container.popBack();
    testing.expectEqual(container.size(), 3);
    testing.expectEqual(container.keyAt(0), 1.0);
    testing.expectEqual(container.valueAt(0), 2);
    testing.expectEqual(container.keyAt(1), 2.0);
    testing.expectEqual(container.valueAt(1), 3);
    testing.expectEqual(container.keyAt(2), 3.0);
    testing.expectEqual(container.valueAt(2), 4);
}
