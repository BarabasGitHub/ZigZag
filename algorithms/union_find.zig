pub fn initialize(parents : []u32) void {
    for(parents) |*e,i| {
        e.* = @intCast(u32, i);
    }
}

pub fn getRoot(parents : []const u32 , index_in: u32) u32 {
    var index = index_in;
    while (index != parents[index]) {
         index = parents[index];
    }
    return index;
}
// gets the root and updates the parents to the grandparents in the process, this keeps the tree structure more shallow
pub fn getRootAndUpdate(parents : []u32, index_in : u32) u32 {
    var index = index_in;
    var parent = parents[index];
    while (index != parent) {
         const grandparent = parents[parent];
         parents[index] = grandparent;
         index = parent;
         parent = grandparent;
    }
    return index;
}

pub fn find(parents : []const u32, index_a : u32, index_b : u32) bool {
    return getRoot(parents, index_a) == getRoot(parents, index_b);
}

pub fn unite(index_a : u32, index_b : u32, parents : []u32) void {
    parents[index_a] = index_b;
}

const testing = @import("std").testing;

test "initialize" {
    var parents : [10]u32 = undefined;
    initialize(parents[0..]);
    for(parents) |e, i| {
        testing.expectEqual(i, usize(e));
    }
}

test "get root" {
    var parents : [10]u32 = undefined;
    initialize(parents[0..]);
    for (parents) |_,i| {
        testing.expectEqual(i, usize(getRoot(parents, @intCast(u32, i))));
    }
    parents[3] = 1;
    testing.expectEqual(u32(1), getRoot(parents, 3));
    parents[1] = 5;
    testing.expectEqual(u32(5), getRoot(parents, 3));
}

test "get root and update" {
    var parents : [10]u32 = undefined;
    initialize(parents[0..]);
    for (parents) |_,i| {
        testing.expectEqual(i, usize(getRootAndUpdate(parents[0..], @intCast(u32, i))));
    }
    parents[3] = 1;
    testing.expectEqual(u32(1), getRootAndUpdate(parents[0..], 3));
    parents[1] = 5;
    testing.expectEqual(u32(5), getRootAndUpdate(parents[0..], 3));
    testing.expectEqual(u32(5), parents[3]);
    testing.expectEqual(u32(5), parents[1]);
    parents[3] = 1;
    parents[5] = 2;
    testing.expectEqual(u32(2), getRootAndUpdate(parents[0..], 3));
    testing.expectEqual(u32(5), parents[3]);
    testing.expectEqual(u32(2), parents[1]);
    testing.expectEqual(u32(2), parents[5]);
    testing.expectEqual(u32(2), getRootAndUpdate(parents[0..], 3));
    testing.expectEqual(u32(2), parents[3]);
    testing.expectEqual(u32(2), parents[1]);
    testing.expectEqual(u32(2), parents[5]);
}

test "find" {
    var parents : [10]u32 = undefined;
    initialize(parents[0..]);
    for (parents) |_,i| {
        testing.expectEqual(true, find(parents, @intCast(u32, i), @intCast(u32, i)));
        if (i != 0) {
            testing.expectEqual(false, find(parents, 0, @intCast(u32, i)));
        }
    }
    parents[3] = 2;
    testing.expectEqual(true, find(parents, 2, 3));
    parents[5] = 2;
    testing.expectEqual(true, find(parents, 2, 5));
    testing.expectEqual(true, find(parents, 3, 5));
    parents[4] = 3;
    testing.expectEqual(true, find(parents, 2, 4));
    testing.expectEqual(true, find(parents, 3, 4));
}

test "unite" {
    var parents : [10]u32 = undefined;
    initialize(parents[0..]);
    unite(1, 2, parents[0..]);
    testing.expectEqual(true, find(parents, 1, 2));
    testing.expectEqual(false, find(parents, 1, 3));
    testing.expectEqual(false, find(parents, 2, 3));
    unite(4, 8, parents[0..]);
    testing.expectEqual(true, find(parents, 4, 8));
    testing.expectEqual(false, find(parents, 2, 4));
    unite(2, 8, parents[0..]);
    testing.expectEqual(true, find(parents, 1, 4));
    testing.expectEqual(true, find(parents, 1, 8));
    testing.expectEqual(true, find(parents, 2, 4));
    testing.expectEqual(true, find(parents, 2, 8));
}
