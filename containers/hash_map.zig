const hf = @import("../algorithms/hash_functions.zig");
const std = @import("std");
usingnamespace @import("multi_value_hash_map.zig");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn HashMap(comptime Key: type, comptime Value: type, comptime hash_function: fn (key: Key) usize, comptime equal_function: fn (a: Key, b: Key) bool) type {
    return struct {
        const HashMapType = MultiValueHashMap(Key, struct { value: Value }, hash_function, equal_function);
        const Self = @This();

        multivalue: HashMapType,

        pub const KeyBucketIterator = HashMapType.KeyBucketIterator;
        pub const Index = HashMapType.Index;

        pub const KeyValueReference = struct {
            key: *const Key,
            value: *Value,
        };

        pub const Iterator = struct {
            parent: HashMapType.Iterator,
            values: [*]Value,

            pub fn init(parent: HashMapType.Iterator, values: []Value) Iterator {
                std.debug.assert(values.len == parent.index_end - parent.index);
                return .{ .parent = parent, .values = values.ptr };
            }

            pub fn next(self: *Iterator) ?KeyValueReference {
                if (self.parent.next()) |key_index| {
                    return KeyValueReference{ .key = key_index.key, .value = &self.values[key_index.index] };
                }
                return null;
            }
        };

        pub fn iterator(self: Self) Iterator {
            return Iterator.init(self.multivalue.iterator(), self.multivalue.soa.span("value"));
        }

        pub fn init(allocator: *Allocator) !Self {
            return Self{ .multivalue = try HashMapType.init(allocator) };
        }

        pub fn deinit(self: Self) void {
            return self.multivalue.deinit();
        }

        pub fn clear(self: *Self) void {
            return self.multivalue.clear();
        }

        pub fn countElements(self: Self) usize {
            return self.multivalue.countElements();
        }

        pub fn empty(self: Self) bool {
            return self.multivalue.empty();
        }

        pub fn countEmptyElements(self: Self) usize {
            return self.multivalue.countEmptyElements();
        }

        pub fn bucketCount(self: Self) usize {
            return self.multivalue.bucketCount();
        }

        pub fn capacity(self: Self) usize {
            return self.multivalue.capacity();
        }

        pub fn loadFactor(self: Self) f32 {
            return self.multivalue.loadFactor();
        }

        pub fn hashValue(self: Self, key: Key) usize {
            return self.multivalue.hashValue(key);
        }

        pub fn bucketIndex(self: Self, key: Key) usize {
            return self.multivalue.bucketIndex(key);
        }

        pub fn setBucketCount(self: *Self, count: usize) !void {
            return self.multivalue.setBucketCount(count);
        }

        pub fn increaseBucketCount(self: *Self) !void {
            return self.multivalue.increaseBucketCount();
        }

        pub fn insert(self: *Self, key: Key, value: Value) !void {
            return self.multivalue.insert(key, .{ .value = value });
        }

        pub fn get(self: Self, key: Key) ?*Value {
            return self.multivalue.get("value", key);
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.multivalue.exists(key);
        }

        /// returns false if the element wasn't there
        pub fn remove(self: *Self, key: Key) ?KeyValueReference {
            if (self.multivalue.remove(key)) |key_index| {
                return KeyValueReference{ .key = key_index.key, .value = self.multivalue.valueAtIndex("value", key_index.index) };
            } else {
                return null;
            }
        }

        pub fn growCapacity(self: *Self) !void {
            return self.multivalue.growCapacity();
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            return self.multivalue.setCapacity(new_capacity);
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

    testing.expect(map.remove(0.0) == null);
    testing.expect(map.remove(0.5) != null);
    testing.expect(map.remove(1.0) == null);
    testing.expect(map.remove(1.5) != null);
    testing.expect(map.remove(2.0) != null);
    testing.expect(map.remove(2.5) == null);
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
