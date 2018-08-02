const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

// this is not really statistics related, but ehh... we need it and I don't know where else to put it for now
fn dotProduct(comptime T: type, a: []const T, b: []const T) T {
    assert(a.len == b.len);
    var s = T(0);
    for(a) |e,i| {
        s += e * b[i];
    }
    return s;
}

pub fn sum(comptime Type: type, input: []const Type) Type {
    var s = Type(0);
    for(input) |i| {
        s += i;
    }
    return s;
}

pub fn average(comptime Type: type, input: []const Type) Type {
    assert(input.len > 0);
    return sum(Type, input) / lengthOfType(Type, input);
}

pub fn covariance(comptime Type: type, input_x: []const Type, input_y: []const Type) Type {
    assert(input_x.len == input_y.len);
    return dotProduct(Type, input_x, input_y) - lengthOfType(Type, input_x) * average(Type, input_x) * average(Type, input_y);
}

pub fn variance(comptime Type: type, input: []const Type) Type {
    return covariance(Type, input, input);
}

pub fn standardDeviation(comptime Type: type, input: []const Type) Type {
    return std.math.sqrt(variance(Type, input));
}


fn lengthOfType(comptime Type: type, input: []const Type) Type {
    return switch (@typeInfo(Type)) {
        builtin.TypeId.Int => @intCast(Type, input.len),
        builtin.TypeId.Float => @intToFloat(Type, input.len),
        else => unreachable,
    };
}

test "dotProduct" {
    const a = []f32{1, 2, 3};
    const b = []f32{3, 4, 5};
    const c = dotProduct(f32, a, b);
    assert(c == 3 + 8 + 15);
}

test "sum" {
    const a = []f32{1, 2, 3};
    const b = sum(f32, a);
    assert(b == 1 + 2 + 3);
}

test "average" {
    const a = []f32{1, 2, 3};
    const b = average(f32, a);
    assert(b == sum(f32, a) / 3);
}

test "covariance" {
    const a = []f32{1, 2, 3};
    const b = []f32{3, 4, 5};
    const c = covariance(f32, a, b);
    assert(c == dotProduct(f32, a, b) - 3 * 2 * 4);
}

test "variance" {
    const a = []f32{1, 2, 3};
    const b = variance(f32, a);
    assert(b == (1 + 4 + 9) - 3 * 4);
}

test "standard deviation" {
    const a = []f32{1, 2, 3};
    const b = standardDeviation(f32, a);
    assert(b == std.math.sqrt(f32(2)));
}
