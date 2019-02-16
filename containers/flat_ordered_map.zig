const NodeKeyValueStorage = @import("node_key_value_storage.zig").NodeKeyValueStorage;
const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;


pub fn FlatOrderedMap(comptime Key: type, comptime Value: type, comptime less: fn (a: Key, b: Key) bool) type {
    return struct {
        pub const Header = struct {
            level : u8,
            parent : u64,
            left_child : u64,
            right_child : u64,
            pub fn children(self: * Header, i: u1) *u64 {return switch(i){ 0 => self.left(), 1=> self.right(), else=> unreachable,};}
            pub fn left(self: * Header) *u64 {return &self.left_child;}
            pub fn right(self: * Header) *u64 {return &self.right_child;}
            pub fn hasRightChild(self: Header) bool {return self.right_child != invalid_index;}
            pub fn hasLeftChild(self: Header) bool {return self.left_child != invalid_index;}
            pub fn hasParent(self: Header) bool {return self.parent != invalid_index;}
        };
        const invalid_index = std.math.maxInt(u64);
        storage: NodeKeyValueStorage(Header, Key, Value),
        root: u64,

        const Self = @This();

        pub const Iterator = struct {

            const Origin = enum(u1) {
                Left,
                Right
            };

            container: * const Self,
            index : ?u64,
            origin: Origin,

            pub const KeyValueReference = struct {
                index : u64,
                container: * const Self,

                pub fn key(self: * const KeyValueReference) Key {
                    return self.container.storage.keyAt(self.index);
                }

                pub fn value(self: * const KeyValueReference) Value {
                    return self.container.storage.valueAt(self.index);
                }
            };

            pub fn current(self: * const Iterator) ?KeyValueReference {
                if (self.index) |index|{
                    return KeyValueReference{.index = index, .container = self.container};
                } else {
                    return null;
                }
            }

            pub fn next(self : *Iterator) ?KeyValueReference {
                const result = self.current() orelse return null;
                const headers = self.container.storage.nodes();
                if (self.origin == Origin.Left){
                    if (self.container.successor(self.index.?)) |successor_index| {
                        self.index = successor_index;
                        return result;
                    }
                }
                if (headers[self.index.?].parent != invalid_index) {
                    if (self.container.isLeftChild(self.index.?)) {
                        self.index = headers[self.index.?].parent;
                        self.origin = Origin.Left;
                    } else {
                        testing.expect(self.container.isRightChild(self.index.?));
                        self.index = headers[self.index.?].parent;
                        self.origin = Origin.Right;
                        _ = self.next();
                    }
                } else {
                    self.index = null;
                }
                return result;
            }
        };

        fn isChild(self: Self, index: u64, leftRight: u1) bool {
            const headers = self.storage.nodes();
            return headers[index].parent != invalid_index and headers[headers[index].parent].children(leftRight).* == index;
        }

        fn isLeftChild(self: Self, index: u64) bool {
            return self.isChild(index, 0);
        }

        fn isRightChild(self: Self, index: u64) bool {
            return self.isChild(index, 1);
        }

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .storage = NodeKeyValueStorage(Header, Key, Value).init(allocator),
                .root = invalid_index,
            };
        }

        pub fn deinit(self: * Self) void {
            self.storage.deinit();
        }

        pub fn empty(self: Self) bool {
            return self.root == invalid_index;
        }

        pub fn count(self: Self) usize {
            return self.storage.size();
        }

        pub fn capacity(self: Self) usize {
            return self.storage.capacity();
        }

        pub fn ensureCapacity(self: * Self, new_capacity: usize) !void {
            try self.storage.ensureCapacity(new_capacity);
        }

        pub fn clear(self: * Self) void {
            self.root = invalid_index;
            self.storage.clear();
        }

        pub fn insert(self: * Self, key: Key, value: Value) !void {
            if (self.empty()) {
                self.root = 0;
                try self.storage.append(Header{.level=0, .parent=invalid_index, .left_child=invalid_index, .right_child=invalid_index,}, key, value);
            } else {
                const insertion_point = self.findInsertionPoint(key);
                const keys = self.storage.keys();
                var headers: []Header = undefined;
                if (less(key, keys[insertion_point])) {
                    const size = @intCast(u64, self.storage.size());
                    try self.storage.append(Header{.level=0, .parent=insertion_point, .left_child=invalid_index, .right_child=invalid_index,}, key, value);
                    headers = self.storage.nodes();
                    headers[insertion_point].left_child = size;
                } else if (less(keys[insertion_point], key)) {
                    const size = @intCast(u64, self.storage.size());
                    try self.storage.append(Header{.level=0, .parent=insertion_point, .left_child=invalid_index, .right_child=invalid_index,}, key, value);
                    headers = self.storage.nodes();
                    headers[insertion_point].right_child = size;
                } else {
                    return error.KeyAlreadyExists;
                }
                var node = insertion_point;
                var next = node;
                while(next != invalid_index) {
                    node = next;
                    node = self.skew(node);
                    node = self.split(node);
                    next = headers[node].parent;
                }
                self.root = node;
            }
        }

        pub fn findInsertionPoint(self: Self, key: Key) u64 {
            testing.expect(!self.empty());
            var keys = self.storage.keys();
            var headers = self.storage.nodes();
            var index = self.root;
            var next = index;
            while(next != invalid_index) {
                index = next;
                if (less(keys[index], key)) {
                    next = headers[index].right().*;
                } else if (less(key, keys[index])) {
                    next = headers[index].left().*;
                } else {
                    break;
                }
            }
            return index;
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.get(key) != null;
        }

        pub fn get(self: Self, key: Key) ?*Value {
            if (self.getIndex(key)) |i|{
                return &self.storage.values()[i];
            } else {
                return null;
            }
        }

        fn getIndex(self: Self, key: Key) ?u64 {
            if (self.empty()) return null;
            const keys = self.storage.keys();
            const headers = self.storage.nodes();
            var index = self.root;
            while(index != invalid_index) {
                if (less(keys[index], key)) {
                    index = headers[index].right().*;
                } else if(less(key, keys[index])) {
                    index = headers[index].left().*;
                } else {
                    return index;
                }
            }
            return null;
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .container = self,
                .index = self.beginIndex(),
                .origin = Iterator.Origin.Left,
            };
        }

        // return false if it wasn't there
        pub fn remove(self: * Self, key: Key) bool {
            if (self.getIndex(key)) |index_in| {
                var index = @intCast(u64, index_in);
                const headers = self.storage.nodes();
                if (self.successor(index)) |successor_index| {
                    testing.expect(successor_index != index);
                    testing.expect(headers[successor_index].left().* == invalid_index);
                    const keys = self.storage.keys();
                    const values = self.storage.values();
                    keys[index] = keys[successor_index];
                    values[index] = values[successor_index];
                    index = successor_index;
                    // The successor doesn't have a left index.
                    // Put the right index on the left so we can remove it with the same code
                    // as if the successor was the index itself without a successor
                    std.mem.swap(u64, headers[index].left(), headers[index].right());
                }


                // Node is a external index with no successor, so assign the left index to the parent
                testing.expect(headers[index].right().* == invalid_index);
                var parent_index = headers[index].parent;
                if (parent_index != invalid_index){
                    const which_child = headers[parent_index].right().* == index;
                    headers[parent_index].children(@boolToInt(which_child)).* = headers[index].left().*;
                } else {
                    self.root = headers[index].left().*;
                }
                // fix up the parent of the (left) child
                if(headers[index].left().* != invalid_index)
                {
                    headers[headers[index].left().*].parent = parent_index;
                }
                // move the last node to the 'index' node and remove the last node
                {
                    const last_index = @intCast(u64, self.storage.size() - 1);
                    if (last_index != index) {
                        testing.expect(index < self.storage.size());
                        var header = self.storage.nodes()[last_index];
                        // fix the parent of the children
                        comptime var i = 0;
                        inline while (i < 2) : (i += 1) {
                            if (header.children(i).* != invalid_index) {
                                headers[header.children(i).*].parent = index;
                            }
                        }
                        // fix the child of the parent
                        if (header.parent != invalid_index) {
                            headers[header.parent].children(@boolToInt(self.isRightChild(last_index))).* = index;
                        }
                        if (parent_index != invalid_index and last_index == parent_index) {
                            parent_index = index;
                        }
                        headers[index] = header;
                        // move the key and value
                        const keys = self.storage.keys();
                        const values = self.storage.values();
                        keys[index] = keys[last_index];
                        values[index] = values[last_index];
                    }
                    self.storage.popBack();
                }
                if (parent_index != invalid_index) {
                    var previous_parent = parent_index;
                    while(parent_index != invalid_index) {
                        if(headers[parent_index].level > 0) {
                            const level = headers[parent_index].level - 1;
                            const right = headers[parent_index].right().*;
                            if ((right != invalid_index and level > headers[right].level) or
                                (headers[parent_index].left().* != invalid_index and level > headers[headers[parent_index].left().*].level))
                            {
                                headers[parent_index].level = level;
                                if (right != invalid_index) {
                                    headers[right].level = std.math.min(level, headers[right].level);
                                }
                                parent_index = self.skew(parent_index);
                                const right_p = headers[parent_index].right();
                                if (right_p.* != invalid_index) {
                                    right_p.* = self.skew(right_p.*);
                                    const right_right_p = headers[right_p.*].right();
                                    if (right_right_p.* != invalid_index) {
                                        right_right_p.* = self.skew(right_right_p.*);
                                    }
                                }
                                parent_index = self.split(parent_index);
                                const new_right_p = headers[parent_index].right();
                                if (new_right_p.* != invalid_index) {
                                    new_right_p.* = self.split(new_right_p.*);
                                }
                            }
                        }
                        previous_parent = parent_index;
                        parent_index = headers[parent_index].parent;
                    }
                    self.root = previous_parent;
                }
                return true;
            } else {
                return false;
            }
        }

        fn successor(self: Self, index: u64) ?u64 {
            const headers = self.storage.nodes();
            var right = headers[index].right().*;
            if (right != invalid_index) {
                return self.allTheWayLeft(right);
            }
            return null;
        }

        fn allTheWayLeft(self: *const Self, start_index: u64) u64 {
            var index = start_index;
            const headers = self.storage.nodes();
            var next = headers[index].left().*;
            // find the leftmost index
            while(next != invalid_index) {
                index = next;
                next = headers[index].left().*;
            }
            return index;
        }

        fn beginIndex(self: *const Self) ?u64 {
            if (self.empty()) return null;
            return self.allTheWayLeft(self.root);
        }


        fn rotate(self: *const Self, root: u64, direction: u1) u64 {
            var headers = self.storage.nodes();
            const child = headers[root].children(direction ^ 1).*;
            const childs_child = headers[child].children(direction).*;
            const parent = headers[root].parent;
            headers[root].parent = child;
            headers[root].children(direction ^ 1).* = childs_child;
            headers[child].children(direction).* = root;
            headers[child].parent = parent;
            const new_root = child;
            if (childs_child != invalid_index) {
                headers[childs_child].parent = root;
            }
            if (parent != invalid_index) {
                if (headers[parent].children(direction).* == root) {
                    headers[parent].children(direction).* = child;
                } else {
                    headers[parent].children(direction ^ 1).* = child;
                }
            }
            return new_root;
        }

        fn split(self: *const Self, root: u64) u64 {
            var new_root = root;
            var headers = self.storage.nodes();
            const right = headers[root].right().*;
            if (right != invalid_index) {
                const right_right = headers[right].right().*;
                if(right_right != invalid_index and headers[right_right].level == headers[root].level) {
                    new_root = self.rotate(root, 0);
                    headers[new_root].level += 1;
                }
            }
            return new_root;
        }

        fn skew(self: *const Self, root: u64) u64 {
            var new_root = root;
            var headers = self.storage.nodes();
            if (headers[root].left().* != invalid_index and headers[headers[root].left().*].level == headers[root].level) {
                new_root = self.rotate(root, 1);
            }
            return new_root;
        }

    };
}

fn less_u32(a: u32, b: u32) bool {
    return a < b;
}

test "FlatOrderedMap initialization" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    testing.expect(container.empty());
    testing.expect(container.count() == 0);
    testing.expect(container.capacity() == 0);
}

test "FlatOrderedMap insert" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    testing.expect(container.count() == 1);
    testing.expect(!container.empty());
    try container.insert(3, 2.5);
    testing.expect(container.count() == 2);
    testing.expect(!container.empty());
    testing.expectError(error.KeyAlreadyExists, container.insert(2, 3.0));
}

test "FlatOrderedMap clear" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    try container.insert(3, 1.5);
    try container.insert(4, 1.5);
    testing.expect(!container.empty());
    testing.expect(container.count() != 0);
    testing.expect(container.capacity() > 0);
    const old_capacity = container.capacity();
    container.clear();
    testing.expect(container.empty());
    testing.expect(container.count() == 0);
    testing.expect(container.capacity() == old_capacity);
}

test "FlatOrderedMap exists" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    testing.expect(!container.exists(2));
    try container.insert(2, 1.5);
    testing.expect(container.exists(2));
    testing.expect(!container.exists(1));
}

test "FlatOrderedMap get" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    testing.expect(container.get(2) == null);
    try container.insert(2, 1.5);
    try container.insert(3, 2.5);
    testing.expect(container.get(2).?.* == 1.5);
    testing.expect(container.get(3).?.* == 2.5);
}

test "FlatOrderedMap ensure capacity" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    testing.expect(container.capacity() == 0);
    try container.ensureCapacity(10);
    testing.expect(container.capacity() == 10);
    try container.ensureCapacity(2);
    testing.expect(container.capacity() == 10);
    try container.insert(2, 1.5);
    try container.insert(3, 2.5);
    try container.ensureCapacity(20);
    testing.expect(container.capacity() == 20);
    testing.expect(container.get(2).?.* == 1.5);
    testing.expect(container.get(3).?.* == 2.5);
}

test "FlatOrderedMap Iterator" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    {
        var iterator = container.iterator();
        testing.expect(iterator.current() == null);
        testing.expect(iterator.next() == null);
        testing.expect(iterator.next() == null);
    }

    const keys = []u32{2, 3, 1};
    const values = []f64{1.5, 2.5, 3.5};

    for (keys) |key, i| {
        try container.insert(key, values[i]);
    }

    const ordered_keys = []u32{1,2,3};
    const ordered_values = []f64{3.5, 1.5, 2.5};
    var iterator = container.iterator();
    var i = u32(0);
    while (iterator.next()) |next| : (i += 1) {
        testing.expect(next.key() == ordered_keys[i]);
        testing.expect(next.value() == ordered_values[i]);
    }
    testing.expect(i == container.count());

    //debug.warn("Header is {} bytes\n", usize(@sizeOf(FlatOrderedMap(u32,u32,less_u32).Header)));
}

test "FlatOrderedMap remove" {
    var container = FlatOrderedMap(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    try container.insert(3, 1.5);
    try container.insert(4, 1.5);

    testing.expect(container.exists(3));
    testing.expect(container.remove(3));
    testing.expect(!container.exists(3));

    testing.expect(container.exists(4));
    testing.expect(container.remove(4));
    testing.expect(!container.exists(4));

    testing.expect(container.count() == 1);
}

test "FlatOrderedMap insert remove many" {
    var allocator = std.heap.DirectAllocator.init();
    defer allocator.deinit();
    var container = FlatOrderedMap(u32, f64, less_u32).init(&allocator.allocator);
    defer container.deinit();

    const many = 1000;
    var keys: [many]u32 = undefined;
    for (keys) |*key, i| {
        key.* = @intCast(u32, i);
    }
    var r = std.rand.DefaultPrng.init(1234);
    r.random.shuffle(u32, keys[0..]);
    for (keys) |key| {
        try container.insert(key, 1.5);
    }
    for (keys) |key| {
        testing.expect(container.remove(key));
    }
    testing.expect(container.empty());
}

fn levelsOk(flatMap: var, index: u64) bool {
    const headers = flatMap.storage.nodes();
    const header0 = headers[index];
    const level0 = header0.level;
    if (header0.hasRightChild()) {
        const header1 = headers[header0.right_child];
        const level1 = header1.level;
        if (level0 < level1) return false;
        if (header1.hasRightChild()) {
            const header2 = headers[header1.right_child];
            const level2 = header2.level;
            if (level1 < level2) return false;
            if (level0 == level2) return false;
        }
    }
    if (header0.hasLeftChild()) {
        const header1 = headers[header0.left_child];
        const level1 = header1.level;
        if (level0 <= level1) return false;
    }
    return true;
}

test "FlatOrderedMap levels" {
    var allocator = std.heap.DirectAllocator.init();
    defer allocator.deinit();
    var container = FlatOrderedMap(u32, f64, less_u32).init(&allocator.allocator);
    defer container.deinit();

    const many = 1000;
    var keys: [many]u32 = undefined;
    for (keys) |*key, i| {
        key.* = @intCast(u32, i);
    }
    var r = std.rand.DefaultPrng.init(1234);
    r.random.shuffle(u32, keys[0..]);
    for (keys) |key| {
        try container.insert(key, 1.5);
        var iterator = container.iterator();
        while (iterator.next()) |next| {
            testing.expect(levelsOk(container, next.index));
        }
    }

}
