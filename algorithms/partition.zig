const std = @import("std");
const testing = std.testing;

// find the next element for which the condition is true
pub fn findNext(comptime T: type, range: []T, comptime condition: fn (element: T) bool) usize {
    for (range) |element, i| {
        if (condition(element)) return i;
    }
    return range.len;
}

// 2-way partition
pub fn partition(comptime T: type, data: []T, comptime predicate: fn (element: T) bool) usize {
    const inverted = struct {
        pub fn predicate(element: T) bool {
            return !predicate(element);
        }
    };
    var begin: usize = 0;
    var end = data.len;
    while (begin < end) {
        begin += findNext(T, data[begin..end], inverted.predicate);
        while (begin < end and inverted.predicate(data[end - 1])) {
            end -= 1;
        }

        if (begin < end) {
            testing.expect((end - begin) > 1);
            std.mem.swap(T, &data[begin], &data[end - 1]);
            begin += 1;
            end -= 1;
        }
    }
    testing.expectEqual(begin, end);
    return begin;
}

pub fn Pair() type {
    return struct {
        first: usize,
        second: usize,
    };
}

// 3-way partition with two pivot points
pub fn dualPivotPartition(comptime T: type, input_data: []T, pivot1: T, pivot2: T, context: var, less: fn (context: @TypeOf(context), a: T, b: T) bool) Pair() {
    // less or equal
    testing.expect(!less(context, pivot2, pivot1));
    var begin: usize = 0;
    var end = input_data.len;
    // first skip elements already in the right place on both sides, so we end up in the middle if we have all the same values (or similar situation)
    while ((end - begin) > 1 and less(context, input_data[begin], pivot1) and less(context, pivot2, input_data[end - 1])) {
        begin += 1;
        end -= 1;
    }

    // first skip elements already correctly in the first partition
    while (begin < end and less(context, input_data[begin], pivot1)) {
        begin += 1;
    }

    // loop over all elements
    const old_begin = begin;
    for (input_data[begin..end]) |*value, i_| {
        const i = i_ + old_begin;
        // if it belongs in the third partition
        if (less(context, pivot2, value.*)) {
            // skip elements already correctly in the third partition
            while (begin < end and less(context, pivot2, input_data[end - 1])) {
                end -= 1;
            }
            if (end <= i) break;
            // put value in the third partition
            std.mem.swap(T, value, &input_data[end - 1]);
            // and exclude it from the second partition
            end -= 1;
        }
        // if it belongs in the first partition
        if (less(context, value.*, pivot1)) {
            // put it in the first partition
            std.mem.swap(T, value, &input_data[begin]);
            // and exclude it from the second
            begin += 1;
        }
        // it belongs in the second (inner) partition
        else {
            // skip
        }
    }
    var result: Pair() = undefined;
    result.first = begin;
    result.second = end;
    return result;
}

pub fn partition3(comptime T: type, data: []T, pivot: T, context: var, less: fn (context: @TypeOf(context), a: T, b: T) bool) Pair() {
    // This is mostly faster than a separate implementation for this Partition3 functionality.
    return dualPivotPartition(T, data, pivot, pivot, context, less);
}

pub inline fn compareAndSwap(comptime T: type, a: *T, b: *T, context: var, less: fn (context: @TypeOf(context), a: T, b: T) bool) void {
    // assume(&a != &b);
    // auto a_t = Move(a);
    // auto b_t = Move(b);
    // auto swap = less(b_t, a_t);
    // a = swap ? Move(b_t) : Move(a_t);
    // b = swap ? Move(a_t) : Move(b_t);
    if (less(context, b.*, a.*)) {
        std.mem.swap(T, a, b);
    }
}

fn sort3(comptime T: type, a: *T, b: *T, c: *T, context: var, less: fn (context: @TypeOf(context), a: T, b: T) bool) void {
    compareAndSwap(T, a, b, context, less);
    compareAndSwap(T, b, c, context, less);
    compareAndSwap(T, a, b, context, less);
}

fn median3(comptime T: type, a_in: *T, b_in: *T, c_in: *T, context: var, comptime less: fn (context: @TypeOf(context), a: T, b: T) bool) *T {
    var a = a_in;
    var b = b_in;
    var c = c_in;
    comptime const ContextType = @TypeOf(context);
    const pointer = struct {
        pub fn less(context2: ContextType, a2: *T, b2: *T) bool {
            return less(context2, a2.*, b2.*);
        }
    };
    sort3(*T, &a, &b, &c, context, pointer.less);
    return b;
}

pub fn partition3ByEstimatedMedian(comptime T: type, data: []T, context: var, comptime less: fn (context: @TypeOf(context), a: T, b: T) bool) Pair() {
    var pivot = median3(T, &data[0], &data[data.len / 2], &data[data.len - 1], context, less);
    std.mem.swap(T, &data[data.len - 1], pivot);
    var current_partition_elements = partition3(T, data[0 .. data.len - 2], data[data.len - 1], context, less);
    std.mem.swap(T, &data[current_partition_elements.second], &data[data.len - 1]);
    return current_partition_elements;
}

pub fn nthElement(comptime T: type, data: []T, partition_point_in: usize, context: var, comptime less: fn (context: @TypeOf(context), a: T, b: T) bool) void {
    var partition_point = partition_point_in;
    testing.expect(partition_point >= 0 and partition_point <= data.len);
    if (data.len == partition_point) return;
    var partition_data = data;
    while (partition_data.len > 16) {
        var current_partition_elements = partition3ByEstimatedMedian(T, partition_data, context, less);
        if (current_partition_elements.first <= partition_point and current_partition_elements.second >= partition_point) {
            return;
        } else if (partition_point < current_partition_elements.first) {
            partition_data = partition_data[0..current_partition_elements.first];
        } else {
            testing.expect(partition_point >= current_partition_elements.second);
            partition_data = partition_data[current_partition_elements.second..];
            partition_point -= current_partition_elements.second;
        }
    }
    std.sort.insertionSort(T, partition_data, context, lessThan);
}

fn isNegative(value: i64) bool {
    return value < 0;
}

fn lessThan(_: void, a: i64, b: i64) bool {
    return a < b;
}

fn makeRandomData(comptime size: usize) [size]i64 {
    var r = std.rand.DefaultPrng.init(1234);
    var values: [size]i64 = undefined;
    for (values) |*value| {
        value.* = @bitCast(i64, r.random.intRangeLessThan(u64, 0, size * 2)) - @intCast(i64, size);
    }
    return values;
}

test "partition" {
    var values = makeRandomData(50);
    var original = values;
    const pivot_value = 0;
    const partition_point = partition(i64, values[0..], isNegative);
    for (values[0..partition_point]) |value| {
        testing.expect(value < pivot_value);
    }
    for (values[partition_point..]) |value| {
        testing.expect(value >= pivot_value);
    }

    // check if we still have all the right values
    std.sort.insertionSort(i64, values[0..], {}, lessThan);
    std.sort.insertionSort(i64, original[0..], {}, lessThan);
    testing.expectEqual(original, values);
}

test "partition with 2 values" {
    var values = [2]i64{ -1, 1 };

    var original = values;
    const pivot_value: i64 = 0;
    const partition_point = partition(i64, values[0..], isNegative);
    for (values[0..partition_point]) |value| {
        testing.expect(value < pivot_value);
    }
    for (values[partition_point..]) |value| {
        testing.expect(value >= pivot_value);
    }

    // check if we still have all the right values
    std.sort.insertionSort(i64, values[0..], {}, lessThan);
    std.sort.insertionSort(i64, original[0..], {}, lessThan);
    testing.expectEqual(original, values);
}

fn testDualPivotPartition(values: []i64, pivot_value1: i64, pivot_value2: i64) void {
    var original = values;
    const pair = dualPivotPartition(i64, values, pivot_value1, pivot_value2, {}, lessThan);
    const smaller = values[0..pair.first];
    const middle = values[pair.first..pair.second];
    const greater = values[pair.second..];
    for (smaller) |value| {
        testing.expect(value < pivot_value1);
    }
    for (middle) |value| {
        testing.expect(value >= pivot_value1);
        testing.expect(value <= pivot_value2);
    }
    for (greater) |value| {
        testing.expect(value > pivot_value2);
    }

    // check if we still have all the right values
    std.sort.insertionSort(i64, values, {}, lessThan);
    std.sort.insertionSort(i64, original, {}, lessThan);
    testing.expectEqual(original, values);
}

test "DualPivotPartition" {
    var values = makeRandomData(50);
    testDualPivotPartition(values[0..], -10, 10);
}

test "DualPivotPartition with fixed values." {
    // It did the wrong thing with these values at some point
    var values = [85]i64{
        -119, -34,  -69,  -56,  2,    -111, -145, -128, -83,  -153, -154, -3,
        -158, -126, -153, -109, -151, -101, -22,  -132, -53,  -97,  -28,  12,
        -102, -95,  -27,  -26,  -139, -30,  -40,  2,    -155, -105, -119, -62,
        -52,  -146, -28,  7,    -107, -160, -112, -134, -30,  -161, -4,   -127,
        -113, -32,  6,    -13,  -117, -31,  -130, -102, -38,  -148, 1,    -155,
        -164, -152, -4,   -151, -130, -34,  -86,  -64,  -66,  -20,  -80,  -48,
        -162, 13,   -128, -78,  -22,  -15,  -47,  2,    -137, -107, -21,  -80,
        -158,
    };
    testDualPivotPartition(values[0..], -91, -66);
}

test "NthElement" {
    var values = makeRandomData(50);

    var original = values;
    const n: usize = 20;
    nthElement(i64, values[0..], n, {}, lessThan);
    for (values[0..n]) |value| {
        testing.expect(value <= values[n]);
    }
    for (values[n + 1 ..]) |value| {
        testing.expect(value >= values[n]);
    }

    // check if we still have all the right values
    std.sort.insertionSort(i64, values[0..], {}, lessThan);
    std.sort.insertionSort(i64, original[0..], {}, lessThan);
    testing.expectEqual(original, values);
}
