const hf = @import("../algorithms/hash_functions.zig");
usingnamespace @import("structure_of_arrays.zig");
const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn AutoMultiValueHashMap(comptime Key: type, comptime Values: type) type {
    return MultiValueHashMap(Key, Values, std.hash_map.getAutoHashFn(Key), std.hash_map.getAutoEqlFn(Key));
}

pub fn MultiValueHashMap(comptime Key: type, comptime Values: type, comptime hash_function: fn (key: Key) usize, comptime equal_function: fn (a: Key, b: Key) bool) type {
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

        const NodeKeyValues = struct {
            node: Node,
            key: Key,
            values: Values,

            pub fn fromNodeKeyAndValues(node: Node, key: Key, values_in: Values) NodeKeyValues {
                var nkv: NodeKeyValues = undefined;
                nkv.node = Node.initEnd(.Used);
                nkv.key = key;
                inline for (std.meta.fields(Values)) |field| {
                    @field(nkv.values, field.name) = @field(values_in, field.name);
                }
                return nkv;
            }
        };

        const SoAType = makeSoAType: {
            var descriptions: [std.meta.fields(Values).len + 2]StructureOfArraysDescription.FieldDescription = undefined;
            descriptions[0].field_type = Node;
            descriptions[0].name = "node";
            descriptions[0].offset = @byteOffsetOf(NodeKeyValues, "node");
            descriptions[1].field_type = Key;
            descriptions[1].name = "key";
            descriptions[1].offset = @byteOffsetOf(NodeKeyValues, "key");
            for (std.meta.fields(Values)) |field, i| {
                descriptions[i + 2].field_type = field.field_type;
                descriptions[i + 2].name = field.name;
                descriptions[i + 2].offset = @byteOffsetOf(NodeKeyValues, "values") + @byteOffsetOf(Values, field.name);
            }
            break :makeSoAType StructureOfArraysAdvanced(.{ .input_struct = NodeKeyValues, .fields = &descriptions });
        };

        buckets: []Node,
        empty_node: Node,
        soa: SoAType,
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

        pub const KeyIndexReference = struct {
            key: *const Key,
            index: usize,
        };

        pub const Iterator = struct {
            index: Index,
            index_end: Index,
            next_nodes: [*]const Node,
            keys: [*]const Key,

            pub fn init(nodes: []const Node, keys: []const Key) Iterator {
                std.debug.assert(nodes.len == keys.len);
                var it = Iterator{
                    .index = 0,
                    .index_end = @intCast(Index, nodes.len),
                    .next_nodes = nodes.ptr,
                    .keys = keys.ptr,
                };
                it.nextNonEmptyIndex();
                return it;
            }

            pub fn next(self: *Iterator) ?KeyIndexReference {
                const current_index = self.index;
                if (current_index == self.index_end) return null;
                self.index += 1;
                self.nextNonEmptyIndex();
                return KeyIndexReference{ .key = &self.keys[current_index], .index = current_index };
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
            return Iterator.init(self.soa.span("node"), self.soa.span("key"));
        }

        pub fn init(allocator: *Allocator) !Self {
            var self = Self{
                .buckets = try allocator.alloc(Node, 1),
                .empty_node = Node.initEnd(.Empty),
                .soa = SoAType.init(allocator),
            };
            self.buckets[0] = Node.initEnd(.Used);
            return self;
        }

        pub fn deinit(self: Self) void {
            self.soa.allocator.free(self.buckets);
            self.soa.deinit();
        }

        pub fn clear(self: *Self) void {
            std.mem.set(Node, self.buckets, Node.initEnd(.Used));
            self.empty_node = Node.initEnd(.Empty);
            self.soa.clear();
        }

        pub fn countElements(self: Self) usize {
            // assuming there are less empty elements, count the emtpy ones.
            return self.soa.size() - self.countEmptyElements();
        }

        pub fn empty(self: Self) bool {
            return self.soa.size() == self.countEmptyElements();
        }

        pub fn countEmptyElements(self: Self) usize {
            var i = self.empty_node;
            var count: usize = 0;
            const next = self.soa.span("node");
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
            return self.soa.capacity();
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
            self.soa.allocator.free(self.buckets);
            self.buckets = try self.soa.allocator.alloc(Node, count);
            std.mem.set(Node, self.buckets, Node.initEnd(.Used));
            var node = self.soa.span("node");
            self.empty_node = Node.initEnd(.Empty);
            const keys = self.soa.span("key");
            var i: Index = 0;
            const size = self.soa.size();
            while (i < size) : (i += 1) {
                var index: *Node = undefined;
                if (node[i].isEmpty()) {
                    // update empty list
                    index = &self.empty_node;
                } else {
                    // put the element in it's new bucket
                    const bucket_index = self.bucketIndex(keys[i]);
                    index = &self.buckets[bucket_index];
                }
                const j = index.*;
                index.index = i;
                node[i] = j;
            }
        }

        pub fn increaseBucketCount(self: *Self) !void {
            try self.setBucketCount(self.bucketCount() * 2);
        }

        pub fn insert(self: *Self, key: Key, values: Values) !void {
            if (self.loadFactor() > 0.88) {
                try self.increaseBucketCount();
            }
            const bucket_index = self.bucketIndex(key);
            var previous_next = &self.buckets[bucket_index];
            var keys = self.soa.span("key");
            var next = self.soa.span("node");
            var i = previous_next.*;
            while (!i.isEnd() and !equal_function(keys[i.index], key)) {
                previous_next = &next[i.index];
                i = previous_next.*;
            } else if (i.isEnd()) {
                if (self.empty_node.isEnd()) {
                    const index = self.soa.size();
                    previous_next.* = .{ .node_type = .Used, .index = @intCast(Index, index) };
                    try self.soa.append(NodeKeyValues.fromNodeKeyAndValues(i, key, values));
                } else {
                    var index = self.empty_node;
                    index.setFilled();
                    self.empty_node = next[index.index];
                    previous_next.* = index;
                    self.soa.setStructure(index.index, NodeKeyValues.fromNodeKeyAndValues(i, key, values));
                }
            } else {
                return error.KeyAlreadyExists;
            }
        }

        pub fn get(self: Self, comptime field_name: []const u8, key: Key) ?*std.meta.fieldInfo(Values, field_name).field_type {
            if (self.keyIndex(key)) |index| {
                return &self.soa.span(field_name)[index];
            } else {
                return null;
            }
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.keyIndex(key) != null;
        }

        pub fn remove(self: *Self, key: Key) ?KeyIndexReference {
            const bucket_index = self.bucketIndex(key);
            if (self.keyIndexFromBucketIndex(key, bucket_index)) |index| {
                var previous = &self.buckets[bucket_index];
                var i = previous.*;
                const next = self.soa.span("node");
                while (i.index != index) {
                    previous = &next[i.index];
                    i = previous.*;
                }
                previous.* = next[index];
                next[index] = self.empty_node;
                self.empty_node = .{ .node_type = .Empty, .index = index };
                return KeyIndexReference{ .key = &self.soa.span("key")[index], .index = index };
            } else {
                return null;
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
                .next_nodes = self.soa.span("node"),
                .keys = self.soa.span("key"),
            };
        }

        pub fn growCapacity(self: *Self) !void {
            try self.soa.growCapacity(1);
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            try self.soa.setCapacity(new_capacity);
        }

        pub fn valueAtIndex(self: Self, comptime field_name: []const u8, index: usize) *std.meta.fieldInfo(Values, field_name).field_type {
            return &self.soa.span(field_name)[index];
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

const TestValues = struct {
    a: u16,
    b: i32,
};

test "initialized MultiValueHashMap state" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
    testing.expectEqual(map.capacity(), 0);
    testing.expectEqual(map.loadFactor(), 0);
    testing.expectEqual(map.bucketIndex(14.88), 0);
    testing.expectEqual(map.bucketCount(), 1);
}

test "increase MultiValueHashMap bucket count" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expectEqual(map.bucketCount(), 1);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 2);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 4);
}

test "set and grow MultiValueHashMap capacity" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
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

test "insert and clear in MultiValueHashMap" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    try map.insert(0.5, .{ .a = 123, .b = 234 });
    testing.expectEqual(map.countElements(), 1);
    try map.insert(1.5, .{ .a = 234, .b = 345 });
    testing.expectEqual(map.countElements(), 2);

    map.clear();
    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
}

test "MultiValueHashMap get and exists" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(0.5, .{ .a = 123, .b = 234 });
    try map.insert(1.5, .{ .a = 234, .b = 345 });
    try map.insert(2.0, .{ .a = 345, .b = 456 });

    testing.expect(!map.exists(0.0));
    testing.expectEqual(@as(?*u16, null), map.get("a", 0.0));
    testing.expectEqual(@as(?*i32, null), map.get("b", 0.0));
    testing.expect(map.exists(0.5));
    testing.expectEqual(@as(u16, 123), map.get("a", 0.5).?.*);
    testing.expectEqual(@as(i32, 234), map.get("b", 0.5).?.*);
    testing.expect(!map.exists(1.0));
    testing.expectEqual(@as(?*u16, null), map.get("a", 1.0));
    testing.expect(map.exists(1.5));
    testing.expectEqual(@as(u16, 234), map.get("a", 1.5).?.*);
    testing.expectEqual(@as(i32, 345), map.get("b", 1.5).?.*);
    testing.expect(map.exists(2.0));
    testing.expectEqual(@as(u16, 345), map.get("a", 2.0).?.*);
    testing.expectEqual(@as(i32, 456), map.get("b", 2.0).?.*);
    testing.expect(!map.exists(2.5));
    testing.expectEqual(@as(?*i32, null), map.get("b", 2.5));
}

test "remove from MultiValueHashMap" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(0.5, .{ .a = 123, .b = 0 });
    try map.insert(1.5, .{ .a = 234, .b = 0 });
    try map.insert(2.0, .{ .a = 345, .b = 0 });

    testing.expect(map.remove(0.0) == null);
    testing.expect(map.remove(0.5) != null);
    testing.expect(map.remove(1.0) == null);
    testing.expect(map.remove(1.5) != null);
    testing.expect(map.remove(2.0) != null);
    testing.expect(map.remove(2.5) == null);
}

test "iterate through MultiValueHashMap" {
    var map = try MultiValueHashMap(f64, TestValues, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    const keys = [_]f64{ 0.5, 1.5, 2.0 };
    var seen = [_]bool{ false, false, false };

    try map.insert(0.5, .{ .a = 123, .b = 0 });
    try map.insert(1.0, .{ .a = 0, .b = 0 });
    try map.insert(1.5, .{ .a = 234, .b = 0 });
    try map.insert(1.7, .{ .a = 0, .b = 0 });
    try map.insert(2.0, .{ .a = 345, .b = 0 });
    try map.insert(3.0, .{ .a = 0, .b = 0 });

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
        testing.expectEqual(map.valueAtIndex("a", kv.index), map.get("a", kv.key.*).?);
        testing.expectEqual(map.valueAtIndex("b", kv.index), map.get("b", kv.key.*).?);
    }
    testing.expectEqual([_]bool{ true, true, true }, seen);
}
