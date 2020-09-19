const hf = @import("../algorithms/hash_functions.zig");
const nkv = @import("node_key_value_storage.zig");
const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn HashMap(comptime Key: type, comptime Value: type, comptime hash_function: fn (key: Key) usize, comptime equal_function: fn (a: Key, b: Key) bool) type {
    return struct {
        const NodeType = packed enum(u1) { Empty, Used };
        const Node = packed struct {
            node_type: NodeType,
            index: Index,

            const end_marker = std.math.maxInt(Index);

            pub fn initEnd(node_type: NodeType) Node {
                return .{ .node_type = node_type, .index = end_marker };
            }

            pub fn isEnd(self: Node) bool {
                return self.index == end_marker;
            }

            pub fn isEmpty(self: Node) bool {
                return switch (self.node_type) {
                    .Empty => true,
                    .Used => false,
                };
            }

            pub fn setFilled(self: *Node) void {
                self.node_type = .Used;
            }
        };

        const Index = u63;

        buckets: []Node,
        empty_node: Node,
        node_key_value_storage: nkv.NodeKeyValueStorage(Node, Key, Value),
        const Self = @This();

        pub const KeyBucketIterator = struct {
            current_node: Node,
            next_nodes: []Node,
            keys: []Key,

            pub fn next(self: *KeyBucketIterator) ?*Key {
                if (!self.current_node.isEnd()) {
                    const key = &self.keys[self.current_node.index];
                    self.current_node = self.next_nodes[self.current_node.index];
                    return key;
                } else {
                    return null;
                }
            }
        };

        pub const KeyValueReference = struct {
            key: *const Key,
            value: *Value,
        };

        pub const Iterator = struct {
            index: Index,
            index_end: Index,
            next_nodes: [*]const Node,
            keys: [*]const Key,
            values: [*]Value,

            pub fn init(nodes: []const Node, keys: []const Key, values: []Value) Iterator {
                std.debug.assert(nodes.len == keys.len);
                std.debug.assert(nodes.len == values.len);
                var it = Iterator{
                    .index = 0,
                    .index_end = @intCast(Index, nodes.len),
                    .next_nodes = nodes.ptr,
                    .keys = keys.ptr,
                    .values = values.ptr,
                };
                it.nextNonEmptyIndex();
                return it;
            }

            pub fn next(self: *Iterator) ?KeyValueReference {
                const current_index = self.index;
                if (current_index == self.index_end) return null;
                self.index += 1;
                self.nextNonEmptyIndex();
                return KeyValueReference{ .key = &self.keys[current_index], .value = &self.values[current_index] };
            }

            fn nextNonEmptyIndex(self: *Iterator) void {
                var next_index = self.index;
                while (next_index != self.index_end and self.next_nodes[next_index].isEmpty()) {
                    next_index += 1;
                }
                self.index = next_index;
            }
        };

        pub fn iterator(self: Self) Iterator {
            return Iterator.init(self.node_key_value_storage.nodes(), self.node_key_value_storage.keys(), self.node_key_value_storage.values());
        }

        pub fn init(allocator: *Allocator) !Self {
            var self = Self{
                .buckets = try allocator.alloc(Node, 1),
                .empty_node = Node.initEnd(.Empty),
                .node_key_value_storage = nkv.NodeKeyValueStorage(Node, Key, Value).init(allocator),
            };
            self.buckets[0] = Node.initEnd(.Used);
            return self;
        }

        pub fn deinit(self: Self) void {
            self.node_key_value_storage.soa.allocator.free(self.buckets);
            self.node_key_value_storage.deinit();
        }

        pub fn clear(self: *Self) void {
            std.mem.set(Node, self.buckets, Node.initEnd(.Used));
            self.empty_node = Node.initEnd(.Empty);
            self.node_key_value_storage.clear();
        }

        pub fn countElements(self: Self) usize {
            // assuming there are less empty elements, count the emtpy ones.
            return self.node_key_value_storage.size() - self.countEmptyElements();
        }

        pub fn empty(self: Self) bool {
            return self.node_key_value_storage.size() == self.countEmptyElements();
        }

        pub fn countEmptyElements(self: Self) usize {
            var i = self.empty_node;
            var count: usize = 0;
            const next = self.node_key_value_storage.nodes();
            while (!i.isEnd()) {
                i = next[i.index];
                count += 1;
            }
            return count;
        }

        pub fn bucketCount(self: Self) usize {
            return self.buckets.len;
        }

        pub fn capacity(self: Self) usize {
            return self.node_key_value_storage.capacity();
        }

        pub fn loadFactor(self: Self) f32 {
            return @intToFloat(f32, self.countElements()) / @intToFloat(f32, self.bucketCount());
        }

        pub fn hashValue(self: Self, key: Key) usize {
            return hash_function(key);
        }

        pub fn bucketIndex(self: Self, key: Key) usize {
            return hash_function(key) % self.bucketCount();
        }

        pub fn setBucketCount(self: *Self, count: usize) !void {
            self.node_key_value_storage.soa.allocator.free(self.buckets);
            self.buckets = try self.node_key_value_storage.soa.allocator.alloc(Node, count);
            std.mem.set(Node, self.buckets, Node.initEnd(.Used));
            var next = self.node_key_value_storage.nodes();
            self.empty_node = Node.initEnd(.Empty);
            const keys = self.node_key_value_storage.keys();
            var i: Index = 0;
            const size = self.node_key_value_storage.size();
            while (i < size) : (i += 1) {
                var index: *Node = undefined;
                if (next[i].isEmpty()) {
                    // update empty list
                    index = &self.empty_node;
                } else {
                    // put the element in it's new bucket
                    const bucket_index = self.bucketIndex(keys[i]);
                    index = &self.buckets[bucket_index];
                }
                const j = index.*;
                index.index = i;
                next[i] = j;
            }
        }

        pub fn increaseBucketCount(self: *Self) !void {
            try self.setBucketCount(self.bucketCount() * 2);
        }

        pub fn insert(self: *Self, key: Key, value: Value) !void {
            if (self.loadFactor() > 0.88) {
                try self.increaseBucketCount();
            }
            const bucket_index = self.bucketIndex(key);
            var previous_next = &self.buckets[bucket_index];
            var keys = self.node_key_value_storage.keys();
            var next = self.node_key_value_storage.nodes();
            var i = previous_next.*;
            while (!i.isEnd() and !equal_function(keys[i.index], key)) {
                previous_next = &next[i.index];
                i = previous_next.*;
            } else if (i.isEnd()) {
                if (self.empty_node.isEnd()) {
                    const index = self.node_key_value_storage.size();
                    previous_next.* = .{ .node_type = .Used, .index = @intCast(Index, index) };
                    try self.node_key_value_storage.append(Node.initEnd(.Used), key, value);
                } else {
                    var index = self.empty_node;
                    index.setFilled();
                    self.empty_node = next[index.index];
                    next[index.index] = i;
                    previous_next.* = index;
                    keys[index.index] = key;
                    self.node_key_value_storage.values()[index.index] = value;
                }
            } else {
                return error.KeyAlreadyExists;
            }
        }

        pub fn get(self: Self, key: Key) ?*Value {
            if (self.keyIndex(key)) |index| {
                return &self.node_key_value_storage.values()[index];
            } else {
                return null;
            }
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.keyIndex(key) != null;
        }

        /// returns false if the element wasn't there
        pub fn remove(self: *Self, key: Key) bool {
            const bucket_index = self.bucketIndex(key);
            if (self.keyIndexFromBucketIndex(key, bucket_index)) |index| {
                var previous = &self.buckets[bucket_index];
                var i = previous.*;
                const next = self.node_key_value_storage.nodes();
                while (i.index != index) {
                    previous = &next[i.index];
                    i = previous.*;
                }
                previous.* = next[index];
                next[index] = self.empty_node;
                self.empty_node = .{ .node_type = .Empty, .index = index };
                return true;
            } else {
                return false;
            }
        }

        fn keyIndex(self: Self, key_in: Key) ?Index {
            const bucket_index = self.bucketIndex(key_in);
            return self.keyIndexFromBucketIndex(key_in, bucket_index);
        }

        fn keyIndexFromBucketIndex(self: Self, key_in: Key, bucket_index: usize) ?Index {
            var bucket_keys = self.bucketKeys(bucket_index);
            var index = bucket_keys.current_node;
            while (bucket_keys.next()) |key| : (index = bucket_keys.current_node) {
                if (equal_function(key.*, key_in)) return index.index;
            }
            return null;
        }

        fn bucketKeys(self: Self, index: usize) KeyBucketIterator {
            return KeyBucketIterator{
                .current_node = self.buckets[index],
                .next_nodes = self.node_key_value_storage.nodes(),
                .keys = self.node_key_value_storage.keys(),
            };
        }

        pub fn growCapacity(self: *Self) !void {
            try self.node_key_value_storage.growCapacity(1);
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            try self.node_key_value_storage.setCapacity(new_capacity);
        }
    };
}

fn test_hash(f: f64) usize {
    const a = @bitCast([8]u8, f);
    return hf.bytestreamHash(&a, 32426578264);
}

fn test_equals(a: f64, b: f64) bool {
    return a == b;
}

test "initialized HashMap state" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
    testing.expectEqual(map.capacity(), 0);
    testing.expectEqual(map.loadFactor(), 0);
    testing.expectEqual(map.bucketIndex(14.88), 0);
    testing.expectEqual(map.bucketCount(), 1);
}

test "increase HashMap bucket count" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expectEqual(map.bucketCount(), 1);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 2);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 4);
}

test "set and grow HashMap capacity" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expectEqual(map.capacity(), 0);
    try map.growCapacity();
    testing.expect(map.capacity() > 0);
    try map.setCapacity(10);
    testing.expect(map.capacity() >= 10);
    const old_capacity = map.capacity();
    try map.growCapacity();
    testing.expect(map.capacity() > old_capacity);
}

test "insert and clear in HashMap" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    try map.insert(0.5, 123);
    testing.expectEqual(map.countElements(), 1);
    try map.insert(1.5, 234);
    testing.expectEqual(map.countElements(), 2);

    map.clear();
    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
}

test "HashMap get and exists" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(0.5, 123);
    try map.insert(1.5, 234);
    try map.insert(2.0, 345);

    testing.expect(!map.exists(0.0));
    testing.expectEqual(map.get(0.0), null);
    testing.expect(map.exists(0.5));
    testing.expectEqual(map.get(0.5).?.*, 123);
    testing.expect(!map.exists(1.0));
    testing.expectEqual(map.get(1.0), null);
    testing.expect(map.exists(1.5));
    testing.expectEqual(map.get(1.5).?.*, 234);
    testing.expect(map.exists(2.0));
    testing.expectEqual(map.get(2.0).?.*, 345);
    testing.expect(!map.exists(2.5));
    testing.expectEqual(map.get(2.5), null);
}

test "remove from HashMap" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(0.5, 123);
    try map.insert(1.5, 234);
    try map.insert(2.0, 345);

    testing.expect(!map.remove(0.0));
    testing.expect(map.remove(0.5));
    testing.expect(!map.remove(1.0));
    testing.expect(map.remove(1.5));
    testing.expect(map.remove(2.0));
    testing.expect(!map.remove(2.5));
}

test "iterate through HashMap" {
    var map = try HashMap(f64, i128, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    const keys = [_]f64{ 0.5, 1.5, 2.0 };
    var seen = [_]bool{ false, false, false };

    try map.insert(0.5, 123);
    try map.insert(1.0, 0);
    try map.insert(1.5, 234);
    try map.insert(1.7, 0);
    try map.insert(2.0, 345);
    try map.insert(3.0, 0);

    _ = map.remove(1.0);
    _ = map.remove(1.7);
    _ = map.remove(3.0);

    var it = map.iterator();
    while (it.next()) |kv| {
        for (keys) |key, i| {
            if (kv.key.* == key) {
                testing.expectEqual(false, seen[i]);
                seen[i] = true;
                break;
            }
        }
        testing.expectEqual(map.get(kv.key.*).?, kv.value);
    }
    testing.expectEqual([_]bool{ true, true, true }, seen);
}
