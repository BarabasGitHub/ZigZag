const NodeKeyValueStorage = @import("node_key_value_storage.zig").NodeKeyValueStorage;
const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const Allocator = std.mem.Allocator;


pub fn FlatOrderedMapInc(comptime Key: type, comptime Value: type, comptime less: fn (a: Key, b: Key) bool) type {
    return struct {
        pub const Header = struct {
            level : u8,
            parent : i64,
            left_child : i64,
            right_child : i64,
            pub fn children(self: * Header, i: u1) *i64 {return switch(i){ 0 => self.left(), 1=> self.right(), else=> unreachable,};}
            pub fn left(self: * Header) *i64 {return &self.left_child;}
            pub fn right(self: * Header) *i64 {return &self.right_child;}
            pub fn hasRightChild(self: Header) bool {return self.right_child != invalid_increment;}
            pub fn hasLeftChild(self: Header) bool {return self.left_child != invalid_increment;}
            pub fn hasParent(self: Header) bool {return self.parent != invalid_increment;}
        };
        const invalid_increment = 0;
        storage: NodeKeyValueStorage(Header, Key, Value),
        root: u63,

        const Self = this;

        pub const Iterator = struct {

            const Origin = enum(u1) {
                Left,
                Right
            };

            container: * const Self,
            index : ?u63,
            origin: Origin,

            pub const KeyValueReference = struct {
                index : u63,
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
                if (headers[self.index.?].parent != invalid_increment) {
                    if (self.container.isLeftChild(self.index.?)) {
                        self.index = addIncrement(self.index.?, headers[self.index.?].parent);
                        self.origin = Origin.Left;
                    } else {
                        assert(self.container.isRightChild(self.index.?));
                        self.index = addIncrement(self.index.?, headers[self.index.?].parent);
                        self.origin = Origin.Right;
                        _ = self.next();
                    }
                } else {
                    self.index = null;
                }
                return result;
            }
        };

        fn isChild(self: Self, index: u63, leftRight: u1) bool {
            const headers = self.storage.nodes();
            return headers[addIncrement(index, headers[index].parent)].children(leftRight).* == -headers[index].parent;
        }

        fn isLeftChild(self: Self, index: u63) bool {
            return self.isChild(index, 0);
        }

        fn isRightChild(self: Self, index: u63) bool {
            return self.isChild(index, 1);
        }

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .storage = NodeKeyValueStorage(Header, Key, Value).init(allocator),
                .root = invalid_increment,
            };
        }

        pub fn deinit(self: * Self) void {
            self.storage.deinit();
        }

        pub fn empty(self: Self) bool {
            return self.root == invalid_increment;
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
            self.root = invalid_increment;
            self.storage.clear();
        }

        pub fn insert(self: * Self, key: Key, value: Value) !void {
            if (self.empty()) {
                self.root = 1;
                try self.storage.append(Header{.level=0, .parent=invalid_increment, .left_child=invalid_increment, .right_child=invalid_increment,}, key, value);
            } else {
                const insertion_point = self.findInsertionPoint(key);
                const keys = self.storage.keys();
                var headers: []Header = undefined;
                if (less(key, keys[insertion_point])) {
                    const size = @intCast(u63, self.storage.size());
                    try self.storage.append(Header{.level=0, .parent=incrementFromIndices(insertion_point, size), .left_child=invalid_increment, .right_child=invalid_increment,}, key, value);
                    headers = self.storage.nodes();
                    headers[insertion_point].left_child = incrementFromIndices(size, insertion_point);
                } else if (less(keys[insertion_point], key)) {
                    const size = @intCast(u63, self.storage.size());
                    try self.storage.append(Header{.level=0, .parent=incrementFromIndices(insertion_point, size), .left_child=invalid_increment, .right_child=invalid_increment,}, key, value);
                    headers = self.storage.nodes();
                    headers[insertion_point].right_child = incrementFromIndices(size, insertion_point);
                } else {
                    return error.KeyAlreadyExists;
                }
                var node = insertion_point;
                var increment: i64 = invalid_increment + 1; // set it to something else than invalid_increment to get a do..while loop.
                while(increment != invalid_increment) {
                    node = self.skew(node);
                    node = self.split(node);
                    increment = headers[node].parent;
                    node = addIncrement(node, increment);
                }
                self.root = node + 1;
            }
        }

        pub fn findInsertionPoint(self: Self, key: Key) u63 {
            assert(!self.empty());
            var keys = self.storage.keys();
            var headers = self.storage.nodes();
            var index = self.root - 1;
            var increment: i64 = self.root;
            while(increment != invalid_increment) : (index = addIncrement(index, increment)) {
                if (less(keys[index], key)) {
                    increment = headers[index].right().*;
                } else if (less(key, keys[index])) {
                    increment = headers[index].left().*;
                } else {
                    return index;
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

        fn getIndex(self: Self, key: Key) ?u63 {
            if (self.empty()) return null;
            const keys = self.storage.keys();
            const headers = self.storage.nodes();
            var index = self.root - 1;
            var increment: i64 = self.root;
            while(increment != invalid_increment) : (index = addIncrement(index, increment)) {
                if (less(keys[index], key)) {
                    increment = headers[index].right().*;
                } else if(less(key, keys[index])) {
                    increment = headers[index].left().*;
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

        fn addIncrement(index: u63, offset: i64) u63 {
            return @intCast(u63, @intCast(i64, index) + offset);
        }

        fn incrementFromIndices(index_a: u63, index_b: u63) i64 {
            return @intCast(i64, index_a) - @intCast(i64, index_b);
        }

        // return false if it wasn't there
        pub fn remove(self: * Self, key: Key) bool {
            if (self.getIndex(key)) |index_in| {
                var index = @intCast(u63, index_in);
                const headers = self.storage.nodes();
                const successor_increment = self.successorIncrement(index);
                var successor_index = addIncrement(index, successor_increment);
                if (successor_increment != invalid_increment) {
                    assert(successor_index != index);
                    assert(headers[successor_index].left().* == invalid_increment);
                    const keys = self.storage.keys();
                    const values = self.storage.values();
                    keys[index] = keys[successor_index];
                    values[index] = values[successor_index];
                    std.mem.swap(u63, &index, &successor_index);
                    // The successor doesn't have a left index.
                    // Put the right index on the left so we can remove it with the same code
                    // as if the successor was the index itself without a successor
                    std.mem.swap(i64, headers[index].left(), headers[index].right());
                }


                // Node is a external index with no successor, so assign the left index to the parent
                assert(headers[index].right().* == invalid_increment);
                const parent_increment = headers[index].parent;
                var parent_index = addIncrement(index, parent_increment);
                if (parent_increment != invalid_increment)
                {
                    const which_child = addIncrement(parent_index, headers[parent_index].right().*) == index;
                    headers[parent_index].children(@boolToInt(which_child)).* = if (headers[index].left().* == invalid_increment) invalid_increment else incrementFromIndices(addIncrement(index, headers[index].left().*), parent_index);
                }
                else
                {
                    if (headers[index].left().* == invalid_increment) {
                        self.root = @intCast(u63, invalid_increment);
                    } else {
                        self.root = addIncrement(index, headers[index].left().*) + 1;
                    }
                }
                // fix up the parent of the (left) child
                if(headers[index].left().* != invalid_increment)
                {
                    headers[addIncrement(index, headers[index].left().*)].parent = if (parent_increment == invalid_increment) invalid_increment else incrementFromIndices(parent_index, addIncrement(index, headers[index].left().*));
                }
                // move the last node to the 'index' node and remove the last node
                {
                    const last_index = @intCast(u63, self.storage.size() - 1);
                    if (last_index != index) {
                        assert(index < self.storage.size());
                        var header = self.storage.nodes()[last_index];
                        // fix the parent of the children
                        comptime var i = 0;
                        inline while (i < 2) : (i += 1) {
                            if (header.children(i).* != invalid_increment) {
                                headers[addIncrement(last_index, header.children(i).*)].parent = incrementFromIndices(index, addIncrement(last_index, header.children(i).*));
                            }
                        }
                        // fix the child of the parent
                        if (header.parent != invalid_increment) {
                            const last_parent = addIncrement(last_index, header.parent);
                            headers[last_parent].children(@boolToInt(self.isRightChild(last_index))).* = incrementFromIndices(index, last_parent);
                        }
                        if (parent_increment != invalid_increment and last_index == parent_index) {
                            parent_index = index;
                            //parent_increment = last_index + header.parent - index;
                        }
                        // fix the pointers of the node
                        headers[index].parent = if (header.parent == invalid_increment) invalid_increment else incrementFromIndices(addIncrement(last_index, header.parent), index);
                        headers[index].left_child = if (header.left_child == invalid_increment) invalid_increment else incrementFromIndices(addIncrement(last_index, header.left_child), index);
                        headers[index].right_child = if (header.right_child == invalid_increment) invalid_increment else incrementFromIndices(addIncrement(last_index, header.right_child), index);
                        // copy the level?
                        headers[index].level = header.level;
                        // move the key and value
                        const keys = self.storage.keys();
                        const values = self.storage.values();
                        keys[index] = keys[last_index];
                        values[index] = values[last_index];
                    }
                    self.storage.popBack();
                }
                if (parent_increment != invalid_increment) {
                    var previous_parent = parent_index;
                    var new_parent_increment = parent_increment;
                    while(new_parent_increment != invalid_increment) {
                        if(headers[parent_index].level > 0) {
                            const level = headers[parent_index].level - 1;
                            const right_increment = headers[parent_index].right().*;
                            const right = addIncrement(parent_index, right_increment);
                            if ((right_increment != invalid_increment and level > headers[right].level) or
                                (headers[parent_index].left().* != invalid_increment and level > headers[addIncrement(parent_index, headers[parent_index].left().*)].level))
                            {
                                headers[parent_index].level = level;
                                if (right_increment != invalid_increment) {
                                    headers[right].level = std.math.min(level, headers[right].level);
                                }
                                parent_index = self.skew(parent_index);
                                // TODO: Not sure if right2 should actually fill right
                                const right2 = self.skew(addIncrement(parent_index, headers[parent_index].right().*));
                                _ = self.skew(addIncrement(right2, headers[right2].right().*));
                                parent_index = self.split(parent_index);
                                _ = self.split(addIncrement(parent_index, headers[parent_index].right().*));
                            }
                        }
                        previous_parent = parent_index;
                        new_parent_increment = headers[parent_index].parent;
                        parent_index = addIncrement(parent_index, new_parent_increment);
                    }
                    self.root = previous_parent + 1;
                }
                return true;
            } else {
                return false;
            }
        }

        fn successorIncrement(self: Self, index: u63) i64 {
            if (self.successor(index)) |successor_index| {
                return incrementFromIndices(successor_index, index);
            } else {
                return invalid_increment;
            }
        }

        fn successor(self: Self, index: u63) ?u63 {
            const headers = self.storage.nodes();
            var right_increment = headers[index].right().*;
            if (right_increment != invalid_increment) {
                return self.allTheWayLeft(addIncrement(index, right_increment));
            }
            return null;
        }

        fn allTheWayLeft(self: *const Self, start_index: u63) u63 {
            var index = start_index;
            const headers = self.storage.nodes();
            var increment = headers[index].left().*;
            // find the leftmost index
            while(increment != invalid_increment) {
                index = addIncrement(index, increment);
                increment = headers[index].left().*;
            }
            return index;
        }

        fn beginIndex(self: *const Self) ?u63 {
            if (self.empty()) return null;
            return self.allTheWayLeft(self.root - 1);
        }


        fn rotate(self: *const Self, root: u63, direction: u1) u63 {
            var headers = self.storage.nodes();
            const child = addIncrement(root, headers[root].children(direction ^ 1).*);
            const childs_child_increment = headers[child].children(direction).*;
            const childs_child = addIncrement(child, childs_child_increment);
            const parent_increment = headers[root].parent;
            const parent = addIncrement(root, parent_increment);
            headers[root].parent = incrementFromIndices(child, root);
            headers[root].children(direction ^ 1).* = if (childs_child_increment == invalid_increment) invalid_increment else incrementFromIndices(childs_child, root);
            headers[child].children(direction).* = incrementFromIndices(root, child);
            headers[child].parent = if (parent_increment == invalid_increment) invalid_increment else incrementFromIndices(parent, child);
            const new_root = child;
            if (childs_child_increment != invalid_increment) {
                headers[childs_child].parent = incrementFromIndices(root, childs_child);
            }
            if (parent_increment != invalid_increment) {
                const increment = incrementFromIndices(child, parent);
                if (headers[parent].children(direction).* == incrementFromIndices(root, parent)) {
                    headers[parent].children(direction).* = increment;
                } else {
                    headers[parent].children(direction ^ 1).* = increment;
                }
            }
            return new_root;
        }

        fn split(self: *const Self, root: u63) u63
        {
            var new_root = root;
            var headers = self.storage.nodes();
            const right = addIncrement(root, headers[root].right().*);
            const right_right_increment = headers[right].right().*;
            if(right_right_increment != invalid_increment and
                    headers[addIncrement(right, right_right_increment)].level == headers[root].level)
            {
                new_root = self.rotate(root, 0);
                headers[new_root].level += 1;
            }
            return new_root;
        }

        fn skew(self: *const Self, root: u63) u63
        {
            var new_root = root;
            var headers = self.storage.nodes();
            if (headers[root].left().* != invalid_increment and
                headers[addIncrement(root, headers[root].left().*)].level == headers[root].level)
            {
                new_root = self.rotate(root, 1);
            }
            return new_root;
        }

    };
}

fn less_u32(a: u32, b: u32) bool {
    return a < b;
}

test "FlatOrderedMapInc initialization" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    assert(container.empty());
    assert(container.count() == 0);
    assert(container.capacity() == 0);
}

test "FlatOrderedMapInc insert" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    assert(container.count() == 1);
    assert(!container.empty());
    try container.insert(3, 2.5);
    assert(container.count() == 2);
    assert(!container.empty());
    debug.assertError(container.insert(2, 3.0), error.KeyAlreadyExists);
}

test "FlatOrderedMapInc clear" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    try container.insert(3, 1.5);
    try container.insert(4, 1.5);
    assert(!container.empty());
    assert(container.count() != 0);
    assert(container.capacity() > 0);
    const old_capacity = container.capacity();
    container.clear();
    assert(container.empty());
    assert(container.count() == 0);
    assert(container.capacity() == old_capacity);
}

test "FlatOrderedMapInc exists" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    assert(!container.exists(2));
    try container.insert(2, 1.5);
    assert(container.exists(2));
    assert(!container.exists(1));
}

test "FlatOrderedMapInc get" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    assert(container.get(2) == null);
    try container.insert(2, 1.5);
    try container.insert(3, 2.5);
    assert(container.get(2).?.* == 1.5);
    assert(container.get(3).?.* == 2.5);
}

test "FlatOrderedMapInc ensure capacity" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    assert(container.capacity() == 0);
    try container.ensureCapacity(10);
    assert(container.capacity() == 10);
    try container.ensureCapacity(2);
    assert(container.capacity() == 10);
    try container.insert(2, 1.5);
    try container.insert(3, 2.5);
    try container.ensureCapacity(20);
    assert(container.capacity() == 20);
    assert(container.get(2).?.* == 1.5);
    assert(container.get(3).?.* == 2.5);
}

test "FlatOrderedMapInc Iterator" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    {
        var iterator = container.iterator();
        assert(iterator.current() == null);
        assert(iterator.next() == null);
        assert(iterator.next() == null);
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
        assert(next.key() == ordered_keys[i]);
        assert(next.value() == ordered_values[i]);
    }
    assert(i == container.count());

    //debug.warn("Header is {} bytes\n", usize(@sizeOf(FlatOrderedMapInc(u32,u32,less_u32).Header)));
}

test "FlatOrderedMapInc remove" {
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(debug.global_allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    try container.insert(3, 1.5);
    try container.insert(4, 1.5);

    assert(container.exists(3));
    assert(container.remove(3));
    assert(!container.exists(3));

    assert(container.exists(4));
    assert(container.remove(4));
    assert(!container.exists(4));

    assert(container.count() == 1);
}

test "FlatOrderedMapInc insert remove many" {
    var allocator = std.heap.DirectAllocator.init();
    defer allocator.deinit();
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(&allocator.allocator);
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
        assert(container.remove(key));
    }
    assert(container.empty());
}

fn levelsOk(flatMap: var, index: u63) bool {
    const headers = flatMap.storage.nodes();
    const header0 = headers[index];
    const level0 = header0.level;
    if (header0.hasRightChild()){
        const header1 = headers[@intCast(u63, @intCast(i64, index) + header0.right_child)];
        const level1 = header1.level;
        if (level0 < level1) return false;
        if (header1.hasRightChild()) {
            const header2 = headers[@intCast(u63, @intCast(i64, index) + header0.right_child + header1.right_child)];
            const level2 = header2.level;
            if (level1 < level2) return false;
            if (level0 == level2) return false;
        }
    }
    if (header0.hasLeftChild()) {
        const header1 = headers[@intCast(u63, @intCast(i64, index) + header0.left_child)];
        const level1 = header1.level;
        if (level0 <= level1) return false;
    }
    return true;
}

test "FlatOrderedMapInc levels" {
    var allocator = std.heap.DirectAllocator.init();
    defer allocator.deinit();
    var container = FlatOrderedMapInc(u32, f64, less_u32).init(&allocator.allocator);
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

    var iterator = container.iterator();
    while (iterator.next()) |next| {
        assert(levelsOk(container, next.index));
    }
}
