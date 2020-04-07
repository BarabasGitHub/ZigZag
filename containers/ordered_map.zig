const NodeKeyValueStorage = @import("node_key_value_storage.zig").NodeKeyValueStorage;
const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn OrderedMap(comptime Key: type, comptime Value: type, comptime less: fn (a: Key, b: Key) bool) type {
    return struct {
        pub const Node = struct {
            level: u8,
            parent: ?*Node,
            left_child: ?*Node,
            right_child: ?*Node,
            key: Key,
            value: Value,

            pub fn initRoot(self: *Node, key: Key, value: Value) void {
                self.init(0, null, null, null, key, value);
            }
            pub fn initLeaf(self: *Node, parent: ?*Node, key: Key, value: Value) void {
                self.init(0, parent, null, null, key, value);
            }
            pub fn init(self: *Node, level: u8, parent: ?*Node, left_child: ?*Node, right_child: ?*Node, key: Key, value: Value) void {
                self.level = level;
                self.parent = parent;
                self.left_child = left_child;
                self.right_child = right_child;
                self.key = key;
                self.value = value;
            }
            pub fn children(self: *Node, i: u1) *?*Node {
                return switch (i) {
                    0 => &self.left_child,
                    1 => &self.right_child,
                    else => unreachable,
                };
            }
            pub fn hasRightChild(self: Node) bool {
                return self.right_child != null;
            }
            pub fn hasLeftChild(self: Node) bool {
                return self.left_child != null;
            }
            pub fn hasParent(self: Node) bool {
                return self.parent != null;
            }
            pub fn isChild(self: *const Node, leftRight: u1) bool {
                return self.parent != null and self.parent.?.children(leftRight).* == self;
            }
            pub fn isLeftChild(self: *const Node) bool {
                return self.isChild(0);
            }
            pub fn isRightChild(self: *const Node) bool {
                return self.isChild(1);
            }
            pub fn successor(node: *Node) ?*Node {
                if (node.right_child) |right| {
                    return right.allTheWayLeft();
                }
                return null;
            }

            pub fn allTheWayLeft(start_node: *Node) *Node {
                var node = start_node;
                while (node.left_child) |next| {
                    node = next;
                }
                return node;
            }

            pub fn rotate(root: *Node, direction: u1) *Node {
                const child = root.children(direction ^ 1).*.?;
                const childs_child = child.children(direction).*;
                const parent = root.parent;
                root.parent = child;
                root.children(direction ^ 1).* = childs_child;
                child.children(direction).* = root;
                child.parent = parent;
                const new_root = child;
                if (childs_child != null) {
                    childs_child.?.parent = root;
                }
                if (parent != null) {
                    if (parent.?.children(direction).* == root) {
                        parent.?.children(direction).* = child;
                    } else {
                        parent.?.children(direction ^ 1).* = child;
                    }
                }
                return new_root;
            }

            pub fn split(root: *Node) *Node {
                var new_root = root;
                if (root.right_child) |right| {
                    if (right.right_child) |right_right| {
                        if (right_right.level == root.level) {
                            new_root = root.rotate(0);
                            new_root.level += 1;
                        }
                    }
                }
                return new_root;
            }

            pub fn skew(root: *Node) *Node {
                var new_root = root;
                if (root.left_child) |left| {
                    if (left.level == root.level) {
                        new_root = root.rotate(1);
                    }
                }
                return new_root;
            }
        };

        root: ?*Node,
        size: usize,
        allocator: *Allocator,

        const Self = @This();

        pub const Iterator = struct {
            const Origin = enum(u1) {
                Left,
                Right,
            };

            node: ?*Node,
            origin: Origin,

            pub const KeyValueReference = struct {
                node: *Node,

                pub fn key(self: *const KeyValueReference) Key {
                    return self.node.key;
                }

                pub fn value(self: *const KeyValueReference) Value {
                    return self.node.value;
                }
            };

            pub fn current(self: *const Iterator) ?KeyValueReference {
                if (self.node) |node| {
                    return KeyValueReference{ .node = node };
                } else {
                    return null;
                }
            }

            pub fn next(self: *Iterator) ?KeyValueReference {
                const result = self.current() orelse return null;
                if (self.origin == Origin.Left) {
                    if (self.node.?.successor()) |successor| {
                        self.node = successor;
                        return result;
                    }
                }
                if (self.node.?.parent) |parent| {
                    if (self.node.?.isLeftChild()) {
                        self.node = parent;
                        self.origin = Origin.Left;
                    } else {
                        testing.expect(self.node.?.isRightChild());
                        self.node = parent;
                        self.origin = Origin.Right;
                        _ = self.next();
                    }
                } else {
                    self.node = null;
                }
                return result;
            }
        };

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .root = null,
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.clear();
        }

        pub fn empty(self: Self) bool {
            return self.root == null;
        }

        pub fn count(self: Self) usize {
            return self.size;
        }

        pub fn clear(self: *Self) void {
            var next = self.root;
            while (next != null) {
                var node = next.?;
                // go down, first left then right
                while (next != null) {
                    node = next.?;
                    // find the leftmost node
                    node = node.allTheWayLeft();
                    // try to go right if we can't go left anymore
                    next = node.right_child;
                }
                // we should be at a leaf
                testing.expect(!node.hasLeftChild() and !node.hasRightChild());
                // go up
                next = node.parent;
                // detach the node from it's parent
                if (next != null) {
                    if (next.?.left_child == node) next.?.left_child = null;
                    if (next.?.right_child == node) next.?.right_child = null;
                }
                // destroy the node
                self.allocator.destroy(node);
            }
            self.root = null;
            self.size = 0;
        }

        pub fn insert(self: *Self, key: Key, value: Value) !void {
            if (self.empty()) {
                var new_node = try self.allocator.create(Node);
                new_node.initRoot(key, value);
                self.root = new_node;
            } else {
                const insertion_point = self.findInsertionPoint(key);
                if (less(key, insertion_point.key)) {
                    var new_node = try self.allocator.create(Node);
                    new_node.initLeaf(insertion_point, key, value);
                    insertion_point.left_child = new_node;
                } else if (less(insertion_point.key, key)) {
                    var new_node = try self.allocator.create(Node);
                    new_node.initLeaf(insertion_point, key, value);
                    insertion_point.right_child = new_node;
                } else {
                    return error.KeyAlreadyExists;
                }
                var node = insertion_point;
                var next: ?*Node = node;
                while (next != null) {
                    node = next.?;
                    node = node.skew();
                    node = node.split();
                    next = node.parent;
                }
                self.root = node;
            }
            self.size += 1;
        }

        pub fn findInsertionPoint(self: Self, key: Key) *Node {
            testing.expect(!self.empty());
            var next = self.root;
            var node = next.?;
            while (next != null) {
                node = next.?;
                if (less(node.key, key)) {
                    next = node.right_child;
                } else if (less(key, node.key)) {
                    next = node.left_child;
                } else {
                    break;
                }
            }
            return node;
        }

        pub fn exists(self: Self, key: Key) bool {
            return self.get(key) != null;
        }

        pub fn get(self: Self, key: Key) ?*Value {
            if (self.getNode(key)) |node| {
                return &node.value;
            } else {
                return null;
            }
        }

        fn getNode(self: Self, key: Key) ?*Node {
            if (self.empty()) return null;
            var node = self.root;
            while (node != null) {
                if (less(node.?.key, key)) {
                    node = node.?.right_child;
                } else if (less(key, node.?.key)) {
                    node = node.?.left_child;
                } else {
                    return node;
                }
            }
            return null;
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .node = self.beginNode(),
                .origin = Iterator.Origin.Left,
            };
        }

        // return false if it wasn't there
        pub fn remove(self: *Self, key: Key) bool {
            if (self.getNode(key)) |node_in| {
                var node = node_in;
                if (node.successor()) |successor| {
                    debug.assert(successor != node);
                    debug.assert(successor.left_child == null);
                    node.key = successor.key;
                    node.value = successor.value;
                    node = successor;
                    // The successor doesn't have a left node.
                    // Put the right node on the left so we can remove it with the same code
                    // as if the successor was the node itself without a successor
                    std.mem.swap(?*Node, &node.left_child, &node.right_child);
                }

                // Node is a external node with no successor, so assign the left node to the parent
                debug.assert(node.right_child == null);
                var parent_node = node.parent;
                if (parent_node) |parent| {
                    const which_child = parent.right_child == node;
                    parent.children(@boolToInt(which_child)).* = node.left_child;
                } else {
                    self.root = node.left_child;
                }
                // fix up the parent of the (left) child
                if (node.left_child) |left_child| {
                    left_child.parent = parent_node;
                }
                self.allocator.destroy(node);
                if (parent_node != null) {
                    var previous_parent = parent_node.?;
                    while (parent_node != null) {
                        var parent = parent_node.?;
                        if (parent.level > 0) {
                            const level = parent.level - 1;
                            const right = parent.right_child;
                            if ((right != null and level > right.?.level) or
                                (parent.left_child != null and level > parent.left_child.?.level))
                            {
                                parent.level = level;
                                if (right != null) {
                                    right.?.level = std.math.min(level, right.?.level);
                                }
                                parent = parent.skew();
                                const right_p = &parent.right_child;
                                if (right_p.* != null) {
                                    right_p.* = right_p.*.?.skew();
                                    const right_right_p = &right_p.*.?.right_child;
                                    if (right_right_p.* != null) {
                                        right_right_p.* = right_right_p.*.?.skew();
                                    }
                                }
                                parent = parent.split();
                                const new_right_p = &parent.right_child;
                                if (new_right_p.* != null) {
                                    new_right_p.* = new_right_p.*.?.split();
                                }
                            }
                        }
                        previous_parent = parent;
                        parent_node = parent.parent;
                    }
                    self.root = previous_parent;
                }
                self.size -= 1;
                return true;
            } else {
                return false;
            }
        }

        fn beginNode(self: *const Self) ?*Node {
            if (self.empty()) return null;
            return self.root.?.allTheWayLeft();
        }
    };
}

fn less_u32(a: u32, b: u32) bool {
    return a < b;
}

test "OrderedMap initialization" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    testing.expect(container.empty());
    testing.expectEqual(container.count(), 0);
}

test "OrderedMap insert" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    testing.expectEqual(container.count(), 1);
    testing.expect(!container.empty());
    try container.insert(3, 2.5);
    testing.expectEqual(container.count(), 2);
    testing.expect(!container.empty());
    testing.expectError(error.KeyAlreadyExists, container.insert(2, 3.0));
}

test "OrderedMap clear" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    try container.insert(2, 1.5);
    try container.insert(3, 1.5);
    try container.insert(4, 1.5);
    testing.expect(!container.empty());
    testing.expect(container.count() != 0);
    container.clear();
    testing.expect(container.empty());
    testing.expectEqual(container.count(), 0);
}

test "OrderedMap exists" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    testing.expect(!container.exists(2));
    try container.insert(2, 1.5);
    testing.expect(container.exists(2));
    testing.expect(!container.exists(1));
}

test "OrderedMap get" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    testing.expect(container.get(2) == null);
    try container.insert(2, 1.5);
    try container.insert(3, 2.5);
    testing.expectEqual(container.get(2).?.*, 1.5);
    testing.expectEqual(container.get(3).?.*, 2.5);
}

test "OrderedMap Iterator" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
    defer container.deinit();

    {
        var iterator = container.iterator();
        testing.expect(iterator.current() == null);
        testing.expect(iterator.next() == null);
        testing.expect(iterator.next() == null);
    }

    const keys = [_]u32{ 2, 3, 1 };
    const values = [_]f64{ 1.5, 2.5, 3.5 };

    for (keys) |key, i| {
        try container.insert(key, values[i]);
    }

    const ordered_keys = [_]u32{ 1, 2, 3 };
    const ordered_values = [_]f64{ 3.5, 1.5, 2.5 };
    var iterator = container.iterator();
    var i : u32 = 0;
    while (iterator.next()) |next| : (i += 1) {
        testing.expectEqual(next.key(), ordered_keys[i]);
        testing.expectEqual(next.value(), ordered_values[i]);
    }
    testing.expectEqual(@as(usize, i), container.count());

    //debug.warn("Header is {} bytes\n", usize(@sizeOf(OrderedMap(u32,u32,less_u32).Header)));
}

test "OrderedMap remove" {
    var container = OrderedMap(u32, f64, less_u32).init(testing.allocator);
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

    testing.expectEqual(container.count(), 1);
}

test "OrderedMap insert remove many" {
    var allocator = std.testing.allocator;
    var container = OrderedMap(u32, f64, less_u32).init(allocator);
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

fn levelsOk(flatMap: var, node0: *@TypeOf(flatMap).Node) bool {
    const level0 = node0.level;
    if (node0.right_child) |node1| {
        const level1 = node1.level;
        if (level0 < level1) return false;
        if (node1.right_child) |node2| {
            const level2 = node2.level;
            if (level1 < level2) return false;
            if (level0 == level2) return false;
        }
    }
    if (node0.left_child) |node1| {
        const level1 = node1.level;
        if (level0 <= level1) return false;
    }
    return true;
}

test "OrderedMap levels" {
    var container = OrderedMap(u32, f64, less_u32).init(std.testing.allocator);
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
            testing.expect(levelsOk(container, next.node));
        }
    }
}
