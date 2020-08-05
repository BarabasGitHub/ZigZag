pub const Float3 = struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,

    pub fn initZero() Float3 {
        return .{ .x = 0, .y = 0, .z = 0 };
    }

    pub fn init(x: f32, y: f32, z: f32) Float3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Float3, other: Float3) Float3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn addToSlice(self: Float3, slice: []Float3) void {
        for (slice) |*e| {
            e.* = add(e.*, self);
        }
    }
};

const testing = @import("std").testing;

test "initialize x y z" {
    const xyz = Float3.init(1, 2, 3);

    testing.expectEqual(@as(f32, 1), xyz.x);
    testing.expectEqual(@as(f32, 2), xyz.y);
    testing.expectEqual(@as(f32, 3), xyz.z);
}

test "initialize as zero" {
    const zero = Float3.initZero();

    testing.expectEqual(@as(f32, 0), zero.x);
    testing.expectEqual(@as(f32, 0), zero.y);
    testing.expectEqual(@as(f32, 0), zero.z);
}

test "adding Float3" {
    var a: Float3 = .{ .x = 1, .y = 2, .z = 3 };
    var b: Float3 = .{ .x = 10, .y = 20, .z = 30 };
    const c = Float3.add(a, b);

    testing.expectEqual(Float3{ .x = 11, .y = 22, .z = 33 }, c);
}

test "addFloat3ToSlice" {
    var forces = [_]Float3{ .{ .x = 1, .y = 0, .z = 0 }, .{ .x = 0, .y = 2, .z = 0 }, .{ .x = 0, .y = 0, .z = 3 } };

    Float3.addToSlice(.{ .x = 10, .y = 20, .z = 30 }, &forces);

    testing.expectEqual(Float3{ .x = 11, .y = 20, .z = 30 }, forces[0]);
    testing.expectEqual(Float3{ .x = 10, .y = 22, .z = 30 }, forces[1]);
    testing.expectEqual(Float3{ .x = 10, .y = 20, .z = 33 }, forces[2]);
}
