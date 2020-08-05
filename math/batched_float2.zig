const std = @import("std");
const fa = @import("float_arrays.zig");

pub fn BatchedFloat2(comptime BatchSize: usize) type {
    return struct {
        x: ArrayType,
        y: ArrayType,

        pub const ArrayType = [BatchSize]f32;
        const Self = @This();

        pub fn zeroInit() Self {
            return uniformInit(0);
        }

        pub fn uniformInit(v: f32) Self {
            var r: Self = undefined;
            std.mem.set(f32, r.x[0..], v);
            std.mem.set(f32, r.y[0..], v);
            return r;
        }

        pub fn arrayInit(a: [BatchSize]f32) Self {
            return Self{
                .x = a,
                .y = a,
            };
        }

        pub fn add(a: Self, b: Self) Self {
            var r: Self = undefined;
            r.x = fa.add(BatchSize, a.x, b.x);
            r.y = fa.add(BatchSize, a.y, b.y);
            return r;
        }

        pub fn subtract(a: Self, b: Self) Self {
            var r: Self = undefined;
            r.x = fa.subtract(BatchSize, a.x, b.x);
            r.y = fa.subtract(BatchSize, a.y, b.y);
            return r;
        }

        pub fn multiply(a: Self, b: Self) Self {
            var r: Self = undefined;
            r.x = fa.multiply(BatchSize, a.x, b.x);
            r.y = fa.multiply(BatchSize, a.y, b.y);
            return r;
        }

        pub fn dot(a: Self, b: Self) ArrayType {
            return fa.multiplyAdd(BatchSize, a.x, b.x, fa.multiply(BatchSize, a.y, b.y));
        }

        pub fn squaredNorm(a: Self) ArrayType {
            return dot(a, a);
        }

        pub fn floor(a: Self) Self {
            var r: Self = undefined;
            r.x = fa.floor(BatchSize, a.x);
            r.y = fa.floor(BatchSize, a.y);
            return r;
        }
    };
}
