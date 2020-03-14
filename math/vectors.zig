const std = @import("std");
const testing = std.testing;

pub fn Vector2d(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();
        pub const ElementCount = 2;
        pub const IndexType = std.meta.IntType(false, std.math.log2_int(usize, ElementCount));

        pub fn initDefault() Self {
            return initUniform(0);
        }

        pub fn init(x: T, y: T) Self {
            return Self{
                .x = x,
                .y = y,
            };
        }

        pub fn initUniform(s: T) Self {
            return init(s, s);
        }

        pub fn get(self: Self, i: IndexType) T {
            return switch (i) {
                0 => self.x,
                1 => self.y,
                else => unreachable,
            };
        }

        pub fn set(self: *Self, v: T, i: IndexType) void {
            const e = switch (i) {
                0 => &self.x,
                1 => &self.y,
                else => unreachable,
            };
            e.* = v;
        }

        pub fn operateOnAllElements(a: Self, b: Self, comptime operation: fn (T, T) T) Self {
            comptime var i = 0;
            var r: Self = undefined;
            inline while (i < ElementCount) : (i += 1) {
                r.set(operation(a.get(i), b.get(i)), i);
            }
            return r;
        }

        const elementOperations = struct {
            pub fn add(a: T, b: T) T {
                return a + b;
            }

            pub fn subtract(a: T, b: T) T {
                return a - b;
            }

            pub fn multiply(a: T, b: T) T {
                return a * b;
            }

            pub fn divide(a: T, b: T) T {
                return a / b;
            }
        };

        pub fn add(a: Self, b: Self) Self {
            return operateOnAllElements(a, b, elementOperations.add);
        }

        pub fn subtract(a: Self, b: Self) Self {
            return operateOnAllElements(a, b, elementOperations.subtract);
        }

        pub fn multiply(a: Self, b: Self) Self {
            return operateOnAllElements(a, b, elementOperations.multiply);
        }

        pub fn divide(a: Self, b: Self) Self {
            return operateOnAllElements(a, b, elementOperations.divide);
        }

        pub fn addScalar(a: Self, s: T) Self {
            return add(a, initUniform(s));
        }

        pub fn subtractScalar(a: Self, s: T) Self {
            return subtract(a, initUniform(s));
        }

        pub fn multiplyScalar(a: Self, s: T) Self {
            return multiply(a, initUniform(s));
        }

        pub fn divideScalar(a: Self, s: T) Self {
            return divide(a, initUniform(s));
        }

        pub fn swizzle(a: Self, comptime indices: [ElementCount]IndexType) Self {
            comptime var i = 0;
            var r: Self = undefined;
            inline while (i < ElementCount) : (i += 1) {
                r.set(a.get(indices[i]), i);
            }
            return r;
        }
    };
}

test "Vector2d init" {
    const d = Vector2d(f32).initDefault();
    testing.expectEqual(d.x, 0);
    testing.expectEqual(d.y, 0);

    const i = Vector2d(f32).init(1, 2);
    testing.expectEqual(i.x, 1);
    testing.expectEqual(i.y, 2);

    const s = Vector2d(f32).initUniform(1);
    testing.expectEqual(s.x, 1);
    testing.expectEqual(s.y, 1);
}

test "Vector2d get" {
    const i = Vector2d(f32).init(1, 2);
    testing.expectEqual(i.get(0), i.x);
    testing.expectEqual(i.get(0), 1);
    testing.expectEqual(i.get(1), i.y);
    testing.expectEqual(i.get(1), 2);
}

test "Vector2d add" {
    const a = Vector2d(f32).init(1, 2);
    const b = Vector2d(f32).init(3, 5);
    const c = a.add(b);
    testing.expectEqual(c.x, 4);
    testing.expectEqual(c.y, 7);
}

test "Vector2d subtract" {
    const a = Vector2d(f32).init(1, 2);
    const b = Vector2d(f32).init(3, 5);
    const c = a.subtract(b);
    testing.expectEqual(c.x, -2);
    testing.expectEqual(c.y, -3);
}

test "Vector2d multiply" {
    const a = Vector2d(f32).init(-1, 2);
    const b = Vector2d(f32).init(3, 5);
    const c = a.multiply(b);
    testing.expectEqual(c.x, -3);
    testing.expectEqual(c.y, 10);
}

test "Vector2d divide" {
    const a = Vector2d(f32).init(3, 5);
    const b = Vector2d(f32).init(-1, 2);
    const c = a.divide(b);
    testing.expectEqual(c.x, -3);
    testing.expectEqual(c.y, 2.5);
}

test "Vector2d add scalar" {
    const a = Vector2d(f32).init(3, 5);
    const c = a.addScalar(2);
    testing.expectEqual(c.x, 5);
    testing.expectEqual(c.y, 7);
}

test "Vector2d subtract scalar" {
    const a = Vector2d(f32).init(3, 5);
    const c = a.subtractScalar(2);
    testing.expectEqual(c.x, 1);
    testing.expectEqual(c.y, 3);
}

test "Vector2d multiply scalar" {
    const a = Vector2d(f32).init(3, 5);
    const c = a.multiplyScalar(3);
    testing.expectEqual(c.x, 9);
    testing.expectEqual(c.y, 15);
}

test "Vector2d divide scalar" {
    const a = Vector2d(f32).init(3, 5);
    const c = a.divideScalar(2);
    testing.expectEqual(c.x, 1.5);
    testing.expectEqual(c.y, 2.5);
}

test "Vector2d swizzle" {
    const a = Vector2d(f32).init(3, 5);
    const b = a.swizzle([_]u1{ 1, 0 });
    const c = a.swizzle([_]u1{ 0, 1 });
    testing.expectEqual(a.x, b.y);
    testing.expectEqual(a.y, b.x);
    testing.expectEqual(a.x, c.x);
    testing.expectEqual(a.y, c.y);
}
