const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

pub fn Data2D(comptime DataType: type) type {
    return struct {
        data: [*]DataType,
        column_count: usize,
        row_count: usize,
        row_byte_pitch: usize,

        const Self = @This();

        pub fn fromSlice(slice: []DataType, column_count: usize, row_count: usize) Self {
            assert(column_count * row_count == slice.len);
            return Self{
                .data = slice.ptr,
                .column_count = column_count,
                .row_count = row_count,
                .row_byte_pitch = (slice.len * @sizeOf(DataType)) / row_count,
            };
        }

        pub fn fromBytes(dataBlob: []align(@alignOf(DataType)) u8, column_count: usize, row_count: usize) Self {
            assert(column_count * row_count * @sizeOf(DataType) <= dataBlob.len);
            return Self{
                .data = @ptrCast([*]DataType, dataBlob.ptr),
                .column_count = column_count,
                .row_count = row_count,
                .row_byte_pitch = dataBlob.len / row_count,
            };
        }

        pub fn subRange(self: Self, column_offset: usize, row_offset: usize, column_count: usize, row_count: usize) Self {
            assert(self.row_count >= row_offset + row_count);
            assert(self.column_count >= column_offset + column_count);
            return Self{
                .data = self.dataPointer(column_offset, row_offset),
                .column_count = column_count,
                .row_count = row_count,
                .row_byte_pitch = self.row_byte_pitch,
            };
        }

        pub fn elementCount(self: Self) usize {
            return self.column_count * self.row_count;
        }

        fn dataPointer(self: Self, column: usize, row: usize) [*]DataType {
            assert(column < self.column_count);
            assert(row < self.row_count);
            const byte_offset = row * self.row_byte_pitch;
            const row_start = @intToPtr([*]DataType, @ptrToInt(self.data) + byte_offset);
            return row_start + column;
        }

        pub fn getRow(self: Self, row: usize) []DataType {
            return self.dataPointer(0, row)[0..self.column_count];
        }

        pub fn getElement(self: Self, column: usize, row: usize) *DataType {
            return &self.dataPointer(column, row)[0];
        }

        const ElementIterator = struct {
            row_data: [*]DataType,
            column: usize,
            column_count: usize,
            row: usize,
            row_count: usize,
            row_byte_pitch: usize,

            pub fn next() ?*DataType {
                const new_column = self.column + 1;
                if (new_column < self.column_count) {
                    self.column = new_column;
                    return &row_data[new_column];
                } else if (self.row + 1 < self.row_count) {
                    self.row += 1;
                    self.row_data = @ptrCast([*]DataType, @ptrCast([*]u8, self.row_data) + self.row_byte_pitch);
                    self.column = 0;
                } else {
                    self.column = self.column_count;
                    self.row = self.row_count;
                    return null;
                }
            }
        };

        pub fn elementIterator(self: Self) ElementIterator {
            return ElementIterator{
                .row_data = self.data,
                .column = 0,
                .column_count = self.column_count,
                .row = 0,
                .row_count = self.row_count,
                .row_byte_pitch = self.row_byte_pitch,
            };
        }
    };
}

test "Data2D from slice" {
    var data: [30]f32 = undefined;
    var range = Data2D(f32).fromSlice(&data, 3, 10);
    testing.expectEqual(range.column_count, 3);
    testing.expectEqual(range.row_count, 10);
    testing.expectEqual(range.row_byte_pitch, 3 * @sizeOf(f32));
    testing.expectEqual(range.elementCount(), 30);

    testing.expectEqual(&data[0 + 0], range.getElement(0, 0));
    testing.expectEqual(&data[0 + 15], range.getElement(0, 5));
    testing.expectEqual(&data[1 + 0], range.getElement(1, 0));
    testing.expectEqual(&data[2 + 15], range.getElement(2, 5));
    testing.expectEqual(&data[2 + 27], range.getElement(2, 9));
}

test "Data2D from bytes" {
    var data: [40]f32 = undefined;
    var range = Data2D(f32).fromBytes(mem.sliceAsBytes(data[0..]), 3, 10);
    testing.expectEqual(range.column_count, 3);
    testing.expectEqual(range.row_count, 10);
    testing.expectEqual(range.row_byte_pitch, 4 * @sizeOf(f32));
    testing.expectEqual(range.elementCount(), 30);
}

test "Data2D data pointer" {
    var data: [40]f32 = undefined;
    var range = Data2D(f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5);
    const pointer = range.dataPointer(4, 3);
    pointer.* = 10;
    testing.expectEqual(data[4 + 8 * 3], 10);
}

test "Data2D get element" {
    var data: [40]f32 = undefined;
    var range = Data2D(f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5);
    const element = range.getElement(4, 3);
    element.* = 10;
    testing.expectEqual(data[4 + 8 * 3], 10);
}

test "Data2D sub range" {
    var data: [40]f32 = undefined;
    var range = Data2D(f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5);
    var subRange = range.subRange(2, 1, 3, 2);
    testing.expectEqual(subRange.dataPointer(0, 0), range.dataPointer(2, 1));
    testing.expectEqual(subRange.column_count, 3);
    testing.expectEqual(subRange.row_count, 2);
    testing.expectEqual(subRange.row_byte_pitch, range.row_byte_pitch);
    testing.expectEqual(subRange.elementCount(), 6);
}

test "Data2D get row" {
    var data: [40]f32 = undefined;
    var range = Data2D(f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5);
    for (range.getRow(2)) |*e, i| {
        e.* = @intToFloat(f32, i);
    }
    testing.expectEqual(range.getRow(2), data[8 * 2 .. 8 * 2 + 6]);
}
