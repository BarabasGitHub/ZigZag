const std = @import("std");
const fa = @import("float_arrays.zig");
const BatchedFloat2 = @import("batched_float2.zig").BatchedFloat2;
const hf = @import("../algorithms/hash_functions.zig");
const assert = std.debug.assert;


fn skewFactor(comptime N: usize) f32 {
    return (@sqrt(f32, @intToFloat(f32, N + 1)) - f32(1)) / @intToFloat(f32, N);
}

fn unskewFactor(comptime N: usize) f32 {
    return (f32(1) - (f32(1) / @sqrt(f32, @intToFloat(f32, N + 1)))) / @intToFloat(f32, N);
}

fn findCornerVertex2(comptime BatchSize: usize, input: BatchedFloat2(BatchSize)) BatchedFloat2(BatchSize) {
    return input.floor();
}

fn skew2(comptime BatchSize: usize, in: BatchedFloat2(BatchSize)) BatchedFloat2(BatchSize) {
    comptime const skewing_factor = comptime BatchedFloat2(BatchSize).uniformInit(skewFactor(2));
    const sum = in.dot(skewing_factor);
    return in.add(BatchedFloat2(BatchSize).arrayInit(sum));
}

fn unskew2(comptime BatchSize: usize, in: BatchedFloat2(BatchSize)) BatchedFloat2(BatchSize) {
    comptime const skewing_factor = comptime BatchedFloat2(BatchSize).uniformInit(unskewFactor(2));
    const sum = in.dot(skewing_factor);
    return in.subtract(BatchedFloat2(BatchSize).arrayInit(sum));
}

fn BatchedLatticePointAndRelativePosition(comptime BatchSize: usize) type {
    return struct {
        lattice_point: BatchedFloat2(BatchSize),
        relative_position: BatchedFloat2(BatchSize),
    };
}

fn calculateLaticePointAndRelativePosition(comptime BatchSize: usize, position: BatchedFloat2(BatchSize)) BatchedLatticePointAndRelativePosition(BatchSize) {
    const skew = skew2(BatchSize, position);
    const lattice_point = findCornerVertex2(BatchSize, skew);
    const corner = unskew2(BatchSize, lattice_point);
    const relative_position = position.subtract(corner);
    return BatchedLatticePointAndRelativePosition(BatchSize){.lattice_point = lattice_point, .relative_position = relative_position};
}


fn calculateSteps2(comptime BatchSize: usize, relative_position: BatchedFloat2(BatchSize)) [3]BatchedFloat2(BatchSize) {
    const one = BatchedFloat2(BatchSize).uniformInit(1);
    const zero = BatchedFloat2(BatchSize).uniformInit(0);
    var step2: BatchedFloat2(BatchSize) = undefined;
    comptime var i = 0;
    inline while (i < BatchSize) {
        if (relative_position.x[i] < relative_position.y[i]) {
            step2.x[i] = zero.x[i];
            step2.y[i] = one.x[i];
        } else {
            step2.x[i] = one.x[i];
            step2.y[i] = zero.x[i];
        }
        i += 1;
    }
    return [3]BatchedFloat2(BatchSize){zero, step2, one};
}

fn interleaveFloat(comptime BatchSize: usize, x: [BatchSize]f32, y: [BatchSize]f32) [BatchSize*2]f32 {
    var r: [BatchSize*2]f32 = undefined;
    for(x)|e, i| {
        r[i*2 + 0] = e;
        r[i*2 + 1] = y[i];
    }
    return r;
}

fn getHashValue(comptime BatchSize: usize, f: BatchedFloat2(BatchSize), seed: usize) [BatchSize]u32 {
    @setFloatMode(@This(), @import("builtin").FloatMode.Strict);
    const value = f.add(BatchedFloat2(BatchSize).zeroInit());
    const abcd = interleaveFloat(BatchSize, f.x, f.y);
    var r: [BatchSize]u32 = undefined;
    for (r)|*e, i| {
        e.* = @truncate(u32, @inlineCall(hf.bytestreamHash, @sliceToBytes(abcd[i*2..(i+1)*2]), seed));
    }
    return r;
}

fn getGradient2(comptime BatchSize: usize, hash: [BatchSize]u32) BatchedFloat2(BatchSize) {
    var r: BatchedFloat2(BatchSize) = undefined;
    for (hash) |h, i| {
        const h1 = (h & 1) << 1;
        const h2 = (h & 2);
        const h4 = (h & 4) >> 2;
        const g0amp = 1 + h4;
        const g0 = g0amp -% (g0amp * h1);

        const g1amp = 2 - h4;
        const g1 = g1amp -% (g1amp * h2);
        r.x[i] = @intToFloat(f32, @bitCast(i32, g0));
        r.y[i] = @intToFloat(f32, @bitCast(i32, g1));
    }
    return r;
}

fn valueFromGradient(comptime BatchSize: usize, x: BatchedFloat2(BatchSize), t: [BatchSize]f32, gradient: BatchedFloat2(BatchSize), gradient_out: ?*BatchedFloat2(BatchSize)) [BatchSize]f32 {
    const gdotx = gradient.dot(x);
    const t2 = fa.multiply(BatchSize, t, t);
    const t4 = fa.multiply(BatchSize, t2, t2);
    const value = fa.multiply(BatchSize, gdotx, t4);
    if(gradient_out) |gradient_out_value| {
        const t3 = fa.multiply(BatchSize, t2, t);
        const t3_8 = fa.multiply(BatchSize, t3, []f32{8} ** BatchSize);
        const gdotx_t3_8 = fa.multiply(BatchSize, gdotx, t3_8);
        const gdotx_t3_8_b = BatchedFloat2(BatchSize).arrayInit(gdotx_t3_8);
        const x_gdotx_t3_8_b = x.multiply(gdotx_t3_8_b);
        const gradient_t4 = gradient.multiply(BatchedFloat2(BatchSize).arrayInit(t4));
        const gradient_t4_x_gdotx_t3_8_b = gradient_t4.subtract(x_gdotx_t3_8_b);
        gradient_out_value.* = gradient_out_value.add(gradient_t4_x_gdotx_t3_8_b);
    }
    return value;
}




pub fn simplexNoise2D(comptime BatchSize: usize, position: BatchedFloat2(BatchSize), gradient_out: ?*BatchedFloat2(BatchSize), seed: u64) [BatchSize]f32 {
    const BatchedFloatType = BatchedFloat2(BatchSize);
    if(gradient_out) |gradient| {
        gradient.* = BatchedFloatType.zeroInit();
    }
    const radius2_2d: [BatchSize]f32 = []f32{0.6} ** BatchSize;

    const lattice_point_and_rel = calculateLaticePointAndRelativePosition(BatchSize, position);
    const lattice_point = lattice_point_and_rel.lattice_point;
    const relative_position = lattice_point_and_rel.relative_position;
    const steps = calculateSteps2(BatchSize, relative_position);
    var value: [BatchSize]f32 = []f32{0} ** BatchSize;
    for(steps) |step| {
        const x = relative_position.subtract(unskew2(BatchSize, step));
        var distance = fa.subtract(BatchSize, radius2_2d, x.squaredNorm());
        distance = fa.max(BatchSize, distance, []f32{0} ** BatchSize);
        if(fa.anyGreaterThanZero(BatchSize, distance)) {
            const vertex = lattice_point.add(step);
            const hash = getHashValue(BatchSize, vertex, seed);
            const gradient = getGradient2(BatchSize, hash);
            const current_value = valueFromGradient(BatchSize, x, distance, gradient, gradient_out);
            value = fa.add(BatchSize, value, current_value);
        }
    }
    const scale: [BatchSize]f32 = []f32{15.5} ** BatchSize; // determined experimentally, 15.75 was too high.
    if (gradient_out) |gradient_out_value| {
       gradient_out_value.* = gradient_out_value.multiply(BatchedFloat2(BatchSize).arrayInit(scale));
    }
    value = fa.multiply(BatchSize, value, scale);
    //assert(-1 <= value and value <= 1);
    return value;
}

fn testSimplex(comptime BatchSize: usize) void {
    const expected_values = [][10]f32{
        [10]f32{-0.6458, 0.1090, -0.6719, 0.1700, 0.5790, 0.08129, -0.2441, -0.7163, -0.1722, 0.03038},
        [10]f32{0.1088, -0.6720, 0.1700, 0.1851, -0.3082, -0.08138, -0.3256, 0.3905, 0.09115, -0.7306},
        [10]f32{-0.6765, 0.1758, 0.5671, -0.7020, 0.08138, 0.1952, -0.5191, 0.03038, -0.9019, 0.1694},
        [10]f32{-0.5275, -0.5908, -0.2382, 0.2441, 0.6502, 0.8440, 0.03038, -0.1289, 0.1995, -0.1340},
        [10]f32{-0.1733, -0.4697, 0.08138, 0.6511, -0.5191, 0.03038, -0.4713, 0.1696, -0.4051, 0.3398},
        [10]f32{0.1497, -0.2441, 0.1300, -0.6279, 0.03038, 0.7314, 0.6875, -0.1360, -0.2894, -0.4518},
        [10]f32{0.08137, -0.7160, -0.8460, 0.09115, 0.2993, -0.6277, -0.1331, -0.6174, 0.1552, 0.2371},
        [10]f32{-0.5848, -0.5208, 0.09115, 0.1300, -0.5978, 0.4022, 0.01180, -0.1552, -0.1952, -0.9161},
        [10]f32{0.6295, 0.09115, 0.8999, -0.1696, -0.4051, -0.01185, -0.1482, -0.2162, 0.3305, 0.05230},
        [10]f32{-0.09115, -0.7291, 0.5979, 0.1330, -0.3162, -0.4518, 0.5859, -0.9157, 0.05230, 0.7318},
    };
    const epsilon = 1e-3;
     //std.debug.warn("BatchSize = {}\n", BatchSize);
    var position: BatchedFloat2(BatchSize) = undefined;
    for([]f32{1,2,3,4,5,6,7,8,9,10}) |x| {
        for([]f32{1,2,3,4,5,6,7,8,9,10}) |y| {
            std.mem.set(f32, position.x[0..], x);
            std.mem.set(f32, position.y[0..], y);
            const seed: usize = 41248592342;
            var gradient = BatchedFloat2(BatchSize).zeroInit();
            const r = simplexNoise2D(BatchSize, position, &gradient, seed);
            //std.debug.warn("Value: {} Gradient: x: {} y: {}\n", r[0], gradient.x[0], gradient.y[0]);
            for (r) |f| {
                assert(-1 < f);
                assert(f <= 1);
                //std.debug.warn("Calculated: {}, expected: {}\n", f, expected_values[@floatToInt(usize, x) - 1][@floatToInt(usize, y) - 1]);
                assert(std.math.approxEq(f32, f, expected_values[@floatToInt(usize, x) - 1][@floatToInt(usize, y) - 1], epsilon));
            }
        }
    }
}

test "simplexNoise2D" {
    testSimplex(1);
    testSimplex(2);
    testSimplex(4);
    testSimplex(8);
    testSimplex(16);
    testSimplex(32);
}
