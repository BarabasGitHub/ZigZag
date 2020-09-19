const hf = @import("../algorithms/hash_functions.zig");
const std = @import("std");
const testing = std.testing;
usingnamespace @import("multi_value_hash_map.zig");

pub fn HashSet(comptime Key: type, comptime hash_function: fn (key: Key) usize, comptime equal_function: fn (a: Key, b: Key) bool) type {
    return struct {
        const HashSetType = MultiValueHashMap(Key, struct {}, hash_function, equal_function);
        const Self = @This();

        hash_map: HashSetType,

        pub const KeyBucketIterator = HashSetType.KeyBucketIterator;
        pub const Iterator = HashSetType.Iterator;
        pub const Index = HashSetType.Index;
        pub const KeyIndexReference = HashSetType.KeyIndexReference;

        pub fn iterator(self: Self) Iterator {
            return self.hash_map.iterator();
        }

        pub fn init(allocator: *std.mem.Allocator) !Self {
            return Self{ .hash_map = try HashSetType.init(allocator) };
        }

        pub fn deinit(self: Self) void {
            return self.hash_map.deinit();
        }

        pub fn clear(self: *Self) void {
            return self.hash_map.clear();
        }

        pub fn countElements(self: Self) usize {
            return self.hash_map.countElements();
        }

        pub fn empty(self: Self) bool {
            return self.hash_map.empty();
        }

        pub fn countEmptyElements(self: Self) usize {
            return self.hash_map.countEmptyElements();
        }

        pub fn bucketCount(self: Self) usize {
            return self.hash_map.bucketCount();
        }

        pub fn capacity(self: Self) usize {
            return self.hash_map.capacity();
        }

        pub fn loadFactor(self: Self) f32 {
            return self.hash_map.loadFactor();
        }

        pub fn hashValue(self: Self, key: Key) usize {
            return self.hash_map.hashValue(key);
        }

        pub fn bucketIndex(self: Self, key: Key) usize {
            return self.hash_map.bucketIndex(key);
        }

        pub fn setBucketCount(self: *Self, count: usize) !void {
            return self.hash_map.setBucketCount(count);
        }

        pub fn increaseBucketCount(self: *Self) !void {
            return self.hash_map.increaseBucketCount();
        }

        pub fn insert(self: *Self, key: Key) !void {
            return self.hash_map.insert(key, .{});
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.hash_map.exists(key);
        }

        /// returns false if the element wasn't there
        pub fn remove(self: *Self, key: Key) ?KeyIndexReference {
            return self.hash_map.remove(key);
        }

        pub fn growCapacity(self: *Self) !void {
            return self.hash_map.growCapacity();
        }

        pub fn setCapacity(self: *Self, new_capacity: usize) !void {
            return self.hash_map.setCapacity(new_capacity);
        }
    };
}

fn test_hash(f: i64) usize {
    const a = @bitCast([8]u8, f);
    return hf.bytestreamHash(&a, 32426578264);
}

fn test_equals(a: i64, b: i64) bool {
    return a == b;
}

test "initialized HashSet state" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
    testing.expectEqual(map.capacity(), 0);
    testing.expectEqual(map.loadFactor(), 0);
    testing.expectEqual(map.bucketIndex(18), 0);
    testing.expectEqual(map.bucketCount(), 1);
}

test "increase HashSet bucket count" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expectEqual(map.bucketCount(), 1);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 2);
    try map.increaseBucketCount();
    testing.expectEqual(map.bucketCount(), 4);
}

test "set and grow HashSet capacity" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
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

test "insert and clear in HashSet" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    testing.expect(map.empty());
    try map.insert(5);
    testing.expectEqual(map.countElements(), 1);
    try map.insert(15);
    testing.expectEqual(map.countElements(), 2);

    map.clear();
    testing.expect(map.empty());
    testing.expectEqual(map.countElements(), 0);
}

test "HashSet get and exists" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(5);
    try map.insert(15);
    try map.insert(20);

    testing.expect(!map.exists(0));
    testing.expect(map.exists(5));
    testing.expect(!map.exists(10));
    testing.expect(map.exists(15));
    testing.expect(map.exists(20));
    testing.expect(!map.exists(25));
}

test "remove from HashSet" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    try map.insert(5);
    try map.insert(15);
    try map.insert(20);

    testing.expect(map.remove(00) == null);
    testing.expect(map.remove(5) != null);
    testing.expect(map.remove(10) == null);
    testing.expect(map.remove(15) != null);
    testing.expect(map.remove(20) != null);
    testing.expect(map.remove(25) == null);
}

test "iterate through HashSet" {
    var map = try HashSet(i64, test_hash, test_equals).init(testing.allocator);
    defer map.deinit();

    const keys = [_]i64{ 5, 15, 20 };
    var seen = [_]bool{ false, false, false };

    try map.insert(5);
    try map.insert(10);
    try map.insert(15);
    try map.insert(17);
    try map.insert(20);
    try map.insert(30);

    _ = map.remove(10);
    _ = map.remove(17);
    _ = map.remove(30);

    var it = map.iterator();
    while (it.next()) |kv| {
        for (keys) |key, i| {
            if (kv.key.* == key) {
                testing.expectEqual(false, seen[i]);
                seen[i] = true;
                break;
            }
        }
        testing.expect(map.exists(kv.key.*));
    }
    testing.expectEqual([_]bool{ true, true, true }, seen);
}
