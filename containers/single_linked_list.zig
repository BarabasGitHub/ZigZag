const std = @import("std");
const debug = std.debug;
const testing = std.testing;
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

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .head = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var node = self.head;
            self.head = null;
            while (node) |n| {
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
            while (node) |n| {
                node = n.next;
                i += 1;
            }
            return i;
        }

        pub fn prepend(self: *Self, value: Value) !void {
            var new_node = try self.allocator.create(Node);
            new_node.value = value;
            new_node.next = self.head;
            self.head = new_node;
        }

        pub fn front(self: Self) *Value {
            testing.expect(self.head != null);
            return &self.head.?.value;
        }

        pub fn popFront(self: *Self) void {
            if (self.head) |node| {
                self.head = node.next;
                self.allocator.destroy(node);
            }
        }

        pub fn insert(self: Self, node: *Node, value: Value) !void {
            var new_node = try self.allocator.create(Node);
            new_node.value = value;
            new_node.next = node.next;
            node.next = new_node;
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .node = self.head,
            };
        }

        pub fn clear(self: *Self) void {
            var node = self.head;
            while (node) |n| {
                node = n.next;
                self.allocator.destroy(n);
            }
            self.head = null;
        }

        pub fn removeAfter(self: *const Self, node: *Node) void {
            const to_remove = node.next.?;
            node.next = to_remove.next;
            self.allocator.destroy(to_remove);
        }

        pub fn splitAfter(self: Self, node: *Node) Self {
            var new = init(self.allocator);
            new.head = node.next;
            node.next = null;
            return new;
        }

        pub fn reverse(self: *Self) void {
            var node = self.head;
            var previous: ?*Node = null;
            while (node) |n| {
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

    testing.expect(container.empty());
    testing.expectEqual(container.count(), 0);
}

test "SingleLinkedList prepend" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    try container.prepend(2);
    testing.expectEqual(container.count(), 2);
}

test "SingleLinkedList front" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    testing.expectEqual(container.front().*, 1);
    try container.prepend(2);
    testing.expectEqual(container.front().*, 2);
}

test "SingleLinkedList popFront" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(1);
    try container.prepend(2);
    container.popFront();
    testing.expectEqual(container.front().*, 1);
}

test "SingleLinkedList iterate" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    var empty_iter = container.iterator();
    testing.expect(empty_iter.next() == null);

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);

    var iter = container.iterator();
    var expected = u32(1);
    while (iter.next()) |value| {
        testing.expectEqual(value.*, expected);
        expected += 1;
    }
}

test "SingleLinkedList insert" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    var iter = container.iterator();
    try container.insert(iter.node.?, 4);
    testing.expectEqual(iter.next().?.*, 3);
    try container.insert(iter.node.?, 5);
    testing.expectEqual(iter.next().?.*, 4);
    testing.expectEqual(iter.next().?.*, 5);
    testing.expect(iter.next() == null);
}

test "SingleLinkedList clear" {
    var container = SingleLinkedList(u32).init(debug.global_allocator);
    defer container.deinit();

    try container.prepend(3);
    try container.prepend(2);
    try container.prepend(1);

    container.clear();
    testing.expect(container.empty());
    testing.expectEqual(container.count(), 0);
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
    testing.expectEqual(iter.next().?.*, 1);
    testing.expectEqual(iter.next().?.*, 3);
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
    while (iter.next()) |value| {
        testing.expectEqual(value.*, expected);
        expected += 1;
    }
    iter = container2.iterator();
    while (iter.next()) |value| {
        testing.expectEqual(value.*, expected);
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
    testing.expectEqual(iter.next().?.*, 1);
    testing.expectEqual(iter.next().?.*, 2);
    testing.expectEqual(iter.next().?.*, 3);
}
