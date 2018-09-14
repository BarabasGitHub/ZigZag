const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const Allocator = std.mem.Allocator;

pub fn SingleLinkedList(comptime Value: type) type {
    return struct {
        head: ?*Node,
        allocator: *Allocator,
        const Self = @This();

        const Node = struct {
            value: Value,
            next: ?*Node,
        };

        const Iterator = struct {
            node: ?*Node,
            pub fn next(self: *Iterator) ?*Value {
                if (self.node) |node| {
                    self.node = node.next;
                    return &node.value;
                } else {
                   return null;
                }
            }
        };

        pub fn init(allocator: * Allocator) Self {
            return Self {
                .head = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: * Self) void {
            var node = self.head;
            self.head = null;
            while(node) |n| {
                node = n.next;
                self.allocator.destroy(n);
            }
        }

        pub fn empty(self: Self) bool {
            return self.head == null;
        }

        pub fn count(self: Self) usize {
            var i = usize(0);
            var node = self.head;
            while(node) |n| {
                node = n.next;
                i += 1;
            }
            return i;
        }

        pub fn prepend(self: * Self, value: Value) !void {
            self.head = try self.allocator.create(Node{.value = value, .next = self.head});
        }

        pub fn front(self: Self) *Value {
            assert(self.head != null);
            return &self.head.?.value;
        }

        pub fn popFront(self: * Self) void {
            if (self.head) |node| {
                self.head = node.next;
                self.allocator.destroy(node);
            }
        }

        pub fn insert(self: Self, node: * Node, value: Value) !void {
            node.next = try self.allocator.create(Node{.value = value, .next = node.next});
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .node = self.head,
            };
        }

        pub fn clear(self: * Self) void {
            var node = self.head;
            while(node) |n| {
                node = n.next;
                self.allocator.destroy(n);
            }
            self.head = null;
        }

        pub fn removeAfter(self: * const Self, node: * Node) void {
            const to_remove = node.next.?;
            node.next = to_remove.next;
            self.allocator.destroy(to_remove);
        }

        pub fn splitAfter(self: Self, node: * Node) Self {
            var new = init(self.allocator);
            new.head = node.next;
            node.next = null;
            return new;
        }

        pub fn reverse(self: * Self) void {
            var node = self.head;
            var previous: ?*Node = null;
            while(node) |n| {
                node = n.next;
                n.next = previous;
                previous = n;
            }
            self.head = previous;
        }
    };
}

test "SingleLinkedList initialization" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    assert(container.empty());
    assert(container.count() == 0);
}

test "SingleLinkedList prepend" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    try container.prepend(2);
    assert(container.count() == 2);
}

test "SingleLinkedList front" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    assert(container.front().* == 1);
    try container.prepend(2);
    assert(container.front().* == 2);
}

test "SingleLinkedList popFront" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    try container.prepend(2);
    container.popFront();
    assert(container.front().* == 1);
}

test "SingleLinkedList iterate" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    var empty_iter = container.iterator();
    assert(empty_iter.next() == null);

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);

    var iter = container.iterator();
    var expected = u32(1);
    while (iter.next()) |value| {
        assert(value.* == expected);
        expected += 1;
    }
}

test "SingleLinkedList insert" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    var iter = container.iterator();
    try container.insert(iter.node.?, 4);
    assert(iter.next().?.* == 3);
    try container.insert(iter.node.?, 5);
    assert(iter.next().?.* == 4);
    assert(iter.next().?.* == 5);
    assert(iter.next() == null);
}

test "SingleLinkedList clear" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);

    container.clear();
    assert(container.empty());
    assert(container.count() == 0);
}

test "SingleLinkedList removeAfter" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);

    var iter = container.iterator();
    container.removeAfter(iter.node.?);
    iter = container.iterator();
    assert(iter.next().?.* == 1);
    assert(iter.next().?.* == 3);
}

test "SingleLinkedList splitAfter" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);
    try container.prepend(0);

    var iter = container.iterator();
    _ = iter.next();
    const container2 = container.splitAfter(iter.node.?);
    iter = container.iterator();
    var expected = u32(0);
    while(iter.next()) |value| {
        assert(value.* == expected);
        expected += 1;
    }
    iter = container2.iterator();
    while(iter.next()) |value| {
        assert(value.* == expected);
        expected += 1;
    }
}

test "SingleLinkedList reverse" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    try container.prepend(2);
    try container.prepend(3);

    container.reverse();
    var iter = container.iterator();
    assert(iter.next().?.* == 1);
    assert(iter.next().?.* == 2);
    assert(iter.next().?.* == 3);
}
