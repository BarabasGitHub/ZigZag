const std = @import("std");

pub fn add(comptime N: usize, a: [N]f32, b: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = e + b[i];
    }
    return r;
}

pub fn subtract(comptime N: usize, a: [N]f32, b: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = e - b[i];
    }
    return r;
}

pub fn multiply(comptime N: usize, a: [N]f32, b: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = e * b[i];
    }
    return r;
}

pub fn multiplyAdd(comptime N: usize, a: [N]f32, b: [N]f32, c: [N]f32) [N]f32 {
    @setFloatMode(@This(), @import("builtin").FloatMode.Optimized);
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = e * b[i] + c[i];
    }
    return r;
}

pub fn max(comptime N: usize, a: [N]f32, b: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = std.math.max(e, b[i]);
    }
    return r;
}

pub fn sqrt(comptime N: usize, a: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = @sqrt(f32, e);
    }
    return r;
}

pub fn floor(comptime N: usize, a: [N]f32) [N]f32 {
    var r: [N]f32 = undefined;
    for (a)|e,i| {
        r[i] = std.math.floor(e);
    }
    return r;
}

pub fn anyGreaterThanZero(comptime N: usize, a: [N]f32) bool {
    for (a) |e| {
        if (e > 0) return true;
    }
    return false;
}
