const hf = @import("../algorithms/hash_functions.zig");
const nkv = @import("node_key_value_storage.zig");
const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn HashMap(comptime Key: type, comptime Value: type, comptime hash_function: fn (key: Key) usize, comptime equal_function: fn (a: Key, b: Key) bool) type {
    return struct {
        buckets : []usize,
        empty_node : usize,
        node_key_value_storage : nkv.NodeKeyValueStorage(usize, Key, Value),
        const Self = @This();

        pub const KeyBucketIterator = struct {
            index : usize,
            nextNodes : []usize,
            keys : []Key,

            pub fn next(self : *KeyBucketIterator) ?*Key {
                if (self.index != std.math.maxInt(usize)) {
                    const key = &self.keys[self.index];
                    self.index = self.nextNodes[self.index];
                    return key;
                } else {
                    return null;
                }
            }
        };

        pub fn init(allocator: *Allocator) !Self {
            var self = Self{
                .buckets = try allocator.alloc(usize, 1),
                .empty_node = std.math.maxInt(usize),
                .node_key_value_storage = nkv.NodeKeyValueStorage(usize, Key, Value).init(allocator),
            };
            self.buckets[0] = std.math.maxInt(usize);
            return self;
        }

        pub fn deinit(self: * Self) void {
            self.node_key_value_storage.allocator.free(self.buckets);
            self.node_key_value_storage.deinit();
        }

        pub fn clear(self: * Self) void {
            std.mem.set(usize, self.buckets, std.math.maxInt(usize));
            self.empty_node = std.math.maxInt(usize);
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
            var count : usize = 0;
            const next = self.node_key_value_storage.nodes();
            while(i != std.math.maxInt(usize)) {
                i = next[i];
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

        pub fn hashValue(self: Self, key : Key) usize {
            return hash_function(key);
        }

        pub fn bucketIndex(self: Self, key : Key) usize {
            return hash_function(key) % self.bucketCount();
        }

        pub fn setBucketCount(self: * Self, count: usize) !void {
            self.node_key_value_storage.allocator.free(self.buckets);
            self.buckets = try self.node_key_value_storage.allocator.alloc(usize, count);
            std.mem.set(usize, self.buckets, std.math.maxInt(usize));
            var next = self.node_key_value_storage.nodes();
            // first mark the emtpy nodes
            {
                var i = self.empty_node;
                while (i != std.math.maxInt(usize)) {
                    const j = next[i];
                    next[i] = std.math.maxInt(usize) - 1;
                    i = j;
                }
            }
            self.empty_node = std.math.maxInt(usize);
            const keys = self.node_key_value_storage.keys();
            var i : usize = 0;
            const size = self.node_key_value_storage.size();
            while(i < size) : (i += 1) {
                var index : * usize = undefined;
                if(next[i] == std.math.maxInt(usize) - 1) {
                    // update empty list
                    index = &self.empty_node;
                } else {
                    // put the element in it's new bucket
                    const bucket_index = self.bucketIndex(keys[i]);
                    index = &self.buckets[bucket_index];
                }
                const j = index.*;
                index.* = i;
                next[i] = j;
            }
        }

        pub fn increaseBucketCount(self: * Self) !void {
            try self.setBucketCount(self.bucketCount() * 2);
        }

        pub fn insert(self: * Self, key: Key, value: Value) !void {
            if(self.loadFactor() > 0.88) {
                try self.increaseBucketCount();
            }
            const bucket_index = self.bucketIndex(key);
            var previous_next = &self.buckets[bucket_index];
            var keys = self.node_key_value_storage.keys();
            var next = self.node_key_value_storage.nodes();
            var i = previous_next.*;
            while(i != std.math.maxInt(usize) and !equal_function(keys[i], key)) {
                previous_next = &next[i];
                i = previous_next.*;
            } else if(i == std.math.maxInt(usize)) {
                if (self.empty_node == std.math.maxInt(usize)) {
                    previous_next.* = self.node_key_value_storage.size();
                    try self.node_key_value_storage.append(std.math.maxInt(usize), key, value);
                } else {
                    const index = self.empty_node;
                    self.empty_node = next[index];
                    next[index] = i;
                    previous_next.* = index;
                    keys[index] = key;
                    self.node_key_value_storage.values()[index] = value;
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
        pub fn remove(self: * Self, key: Key) bool {
            const bucket_index = self.bucketIndex(key);
            if (self.keyIndexFromBucketIndex(key, bucket_index)) |index| {
                var previous = &self.buckets[bucket_index];
                var i = previous.*;
                const next = self.node_key_value_storage.nodes();
                while(i != index) {
                    previous = &next[i];
                    i = previous.*;
                }
                previous.* = next[index];
                next[index] = self.empty_node;
                self.empty_node = index;
                return true;
            } else {
                return false;
            }
        }

        fn keyIndex(self: Self, key_in: Key) ?usize {
            const bucket_index = self.bucketIndex(key_in);
            return self.keyIndexFromBucketIndex(key_in, bucket_index);
        }

        fn keyIndexFromBucketIndex(self: Self, key_in: Key, bucket_index: usize) ?usize {
            var bucket_keys = self.bucketKeys(bucket_index);
            var index = bucket_keys.index;
            while (bucket_keys.next()) |key| : (index = bucket_keys.index) {
                if (equal_function(key.*, key_in)) return index;
            }
            return null;
        }

        fn bucketKeys(self: Self, index: usize) KeyBucketIterator {
            return KeyBucketIterator{
                .index = self.buckets[index],
                .nextNodes = self.node_key_value_storage.nodes(),
                .keys = self.node_key_value_storage.keys(),
            };
        }

        pub fn growCapacity(self : * Self) !void {
            try self.node_key_value_storage.growCapacity(1);
        }

        pub fn setCapacity(self : * Self, new_capacity : usize) !void {
            try self.node_key_value_storage.setCapacity(new_capacity);
        }
    };
}

fn test_hash(f : f64) usize {
    const a = @bitCast([8]u8, f);
    return hf.bytestreamHash(&a, 32426578264);
}

fn test_equals(a : f64, b : f64) bool {
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
    testing.expectEqual(map.capacity(), 10);
    try map.growCapacity();
    testing.expect(map.capacity() > 10);
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
