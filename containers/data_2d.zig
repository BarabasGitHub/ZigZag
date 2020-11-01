const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

fn SingleToMultiElementPointer(comptime P: type) type {
    const ChildType = std.meta.Child(P);
    const alignment = std.meta.alignment(P);

    if (std.meta.trait.isConstPtr(P))
        return [*]align(alignment) const ChildType;
    return [*]align(alignment) ChildType;
}

fn SingleElementPointerToSlice(comptime P: type) type {
    const ChildType = std.meta.Child(P);
    const alignment = std.meta.alignment(P);

    if (std.meta.trait.isConstPtr(P))
        return []align(alignment) const ChildType;
    return []align(alignment) ChildType;
}

pub fn Data2D(comptime SingleElementPointerDataType: type) type {
    comptime const MultiElementPointerDataType = SingleToMultiElementPointer(SingleElementPointerDataType);
    comptime const SliceDataType = SingleElementPointerToSlice(SingleElementPointerDataType);
    comptime const DataType = std.meta.Child(SingleElementPointerDataType);

    return struct {
        data: MultiElementPointerDataType,
        column_count: usize,
        row_count: usize,
        row_byte_pitch: usize,

        const Self = @This();

        pub fn fromSlice(slice: SliceDataType, column_count: usize, row_count: usize) Self {
            assert(column_count * row_count == slice.len);
            return Self{
                .data = slice.ptr,
                .column_count = column_count,
                .row_count = row_count,
                .row_byte_pitch = column_count * @sizeOf(DataType),
            };
        }

        pub fn fromBytes(dataBlob: []align(std.meta.alignment(MultiElementPointerDataType)) u8, column_count: usize, row_count: usize, row_byte_pitch: usize) Self {
            assert(column_count * row_count * @sizeOf(DataType) <= dataBlob.len);
            assert(dataBlob.len / row_count == row_byte_pitch);
            return Self{
                .data = @ptrCast([*]DataType, dataBlob.ptr),
                .column_count = column_count,
                .row_count = row_count,
                .row_byte_pitch = row_byte_pitch,
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

        fn dataPointer(self: Self, column: usize, row: usize) MultiElementPointerDataType {
            assert(column < self.column_count);
            assert(row < self.row_count);
            const byte_offset = row * self.row_byte_pitch;
            const row_start = @intToPtr([*]DataType, @ptrToInt(self.data) + byte_offset);
            return row_start + column;
        }

        pub fn getRow(self: Self, row: usize) SliceDataType {
            return self.dataPointer(0, row)[0..self.column_count];
        }

        pub fn getElement(self: Self, column: usize, row: usize) SingleElementPointerDataType {
            return &self.dataPointer(column, row)[0];
        }

        pub usingnamespace enableForMutableData(struct {
            pub fn toConst(self: Self) Data2D(*const DataType) {
                return .{
                    .data = self.data,
                    .column_count = self.column_count,
                    .row_count = self.row_count,
                    .row_byte_pitch = self.row_byte_pitch,
                };
            }

            pub fn setAll(self: Self, value: DataType) void {
                var it = self.rowIterator();
                while (it.next()) |row| {
                    std.mem.set(DataType, row, value);
                }
            }

            // must have the same dimensions
            pub fn copyContentFrom(self: Self, other: Data2D(*const DataType)) void {
                assert(self.row_count == other.row_count and self.column_count == other.column_count);
                var row_index: usize = 0;
                while (row_index < self.row_count) : (row_index += 1) {
                    std.mem.copy(DataType, self.getRow(row_index), other.getRow(row_index));
                }
            }
        });

        const RowIterator = struct {
            row_data: MultiElementPointerDataType,
            row_data_end: MultiElementPointerDataType,
            column_count: usize,
            row_byte_pitch: usize,

            // not valid before calling next or after next returns null
            pub fn current(self: RowIterator) SliceDataType {
                return self.row_data[0..self.column_count];
            }

            pub fn next(self: *RowIterator) ?SliceDataType {
                self.row_data = @intToPtr(MultiElementPointerDataType, @ptrToInt(self.row_data) + self.row_byte_pitch);
                if (self.row_data != self.row_data_end) {
                    return self.current();
                } else {
                    return null;
                }
            }
        };

        pub fn rowIterator(self: Self) RowIterator {
            const one_before_start = @intToPtr(MultiElementPointerDataType, @ptrToInt(self.data) - self.row_byte_pitch);
            const one_past_end = @intToPtr(MultiElementPointerDataType, @ptrToInt(self.data) + self.row_byte_pitch * self.row_count);
            return .{ .row_data = one_before_start, .row_data_end = one_past_end, .column_count = self.column_count, .row_byte_pitch = self.row_byte_pitch };
        }

        const ElementIterator = struct {
            row_iterator: RowIterator,
            column: usize,

            pub fn next(self: *ElementIterator) ?SingleElementPointerDataType {
                if (self.column < self.row_iterator.column_count) {
                    defer self.column += 1;
                    return &self.row_iterator.current()[self.column];
                } else if (self.row_iterator.next() != null) {
                    self.column = 0;
                    return self.next();
                } else {
                    return null;
                }
            }
        };

        pub fn elementIterator(self: Self) ElementIterator {
            return ElementIterator{
                .row_iterator = self.rowIterator(),
                .column = self.column_count,
            };
        }

        pub fn isSameSizeAndHasEqualData(self: Self, other: Self) bool {
            return self.column_count == other.column_count and self.row_count == other.row_count and ele: {
                var r = 0;
                while (r < self.row_count) : (r += 1) {
                    var self_row = self.getRow(r);
                    var other_row = other.getRow(r);
                    var c = 0;
                    while (c < self.column_count) : (c += 1) {
                        if (self_row[c] != other_row[c]) break :ele false;
                    }
                }
                break :ele true;
            };
        }

        // only works when row_byte_pitch == column_count * @sizeOf(DataType)
        pub fn toSlice(self: Self) SliceDataType {
            assert(self.column_count * @sizeOf(DataType) == self.row_byte_pitch);
            return self.data[0..self.elementCount()];
        }

        fn enableForMutableData(comptime t: type) type {
            if (std.meta.trait.isConstPtr(MultiElementPointerDataType)) {
                return struct {};
            } else {
                return t;
            }
        }

        pub const testing = struct {
            pub fn expectEqualDimensions(expected: Self, actual: Self) void {
                if (expected.row_count != actual.row_count or expected.column_count != actual.column_count) {
                    std.debug.panic("Dimensions differ. expected r: {} c: {}, found r: {} c: {}", .{ expected.row_count, expected.column_count, actual.row_count, actual.column_count });
                }
            }

            pub fn expectEqualContent(expected: Self, actual: Self) void {
                Self.testing.expectEqualDimensions(expected, actual);
                var row_index: usize = 0;
                while (row_index < expected.row_count) : (row_index += 1) {
                    const expected_row = expected.getRow(row_index);
                    const actual_row = actual.getRow(row_index);
                    for (expected_row) |e, column_index| {
                        const a = actual_row[column_index];
                        if (!std.meta.eql(e, a)) {
                            switch (@typeInfo(DataType)) {
                                .Array => {
                                    switch (e.len) {
                                        1 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, e[0], a[0] }),
                                        2 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{}], found [{},{}]", .{ row_index, column_index, e[0], e[1], a[0], a[1] }),
                                        3 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{},{}], found [{},{},{}]", .{ row_index, column_index, e[0], e[1], e[2], a[0], a[1], a[2] }),
                                        4 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{},{},{}], found [{},{},{},{}]", .{ row_index, column_index, e[0], e[1], e[2], e[3], a[0], a[1], a[2], a[3] }),
                                        else => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, expected, a }),
                                    }
                                },
                                else => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, e, a }),
                            }
                        }
                    }
                }
            }

            pub fn expectEqualToValue(expected: DataType, actual: Self) void {
                var row_index: usize = 0;
                while (row_index < actual.row_count) : (row_index += 1) {
                    const actual_row = actual.getRow(row_index);
                    for (actual_row) |a, column_index| {
                        if (!std.meta.eql(expected, a)) {
                            switch (@typeInfo(DataType)) {
                                .Array => {
                                    switch (expected.len) {
                                        1 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, expected[0], a[0] }),
                                        2 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{}], found [{},{}]", .{ row_index, column_index, expected[0], expected[1], a[0], a[1] }),
                                        3 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{},{}], found [{},{},{}]", .{ row_index, column_index, expected[0], expected[1], expected[2], a[0], a[1], a[2] }),
                                        4 => std.debug.panic("Coordinates r: {} c: {} incorrect. expected [{},{},{},{}], found [{},{},{},{}]", .{ row_index, column_index, expected[0], expected[1], expected[2], expected[3], a[0], a[1], a[2], a[3] }),
                                        else => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, expected, a }),
                                    }
                                },
                                else => std.debug.panic("Coordinates r: {} c: {} incorrect. expected {}, found {}", .{ row_index, column_index, expected, a }),
                            }
                        }
                    }
                }
            }
        };
    };
}

test "Data2D from slice" {
    var data: [30]f32 = undefined;
    var range = Data2D(*f32).fromSlice(&data, 3, 10);
    std.testing.expectEqual(range.column_count, 3);
    std.testing.expectEqual(range.row_count, 10);
    std.testing.expectEqual(range.row_byte_pitch, data.len * @sizeOf(f32) / range.row_count);
    std.testing.expectEqual(range.elementCount(), 30);

    std.testing.expectEqual(&data[0 + 0], range.getElement(0, 0));
    std.testing.expectEqual(&data[0 + 15], range.getElement(0, 5));
    std.testing.expectEqual(&data[1 + 0], range.getElement(1, 0));
    std.testing.expectEqual(&data[2 + 15], range.getElement(2, 5));
    std.testing.expectEqual(&data[2 + 27], range.getElement(2, 9));
}

test "Data2D from bytes" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 3, 10, 16);
    std.testing.expectEqual(range.column_count, 3);
    std.testing.expectEqual(range.row_count, 10);
    std.testing.expectEqual(range.row_byte_pitch, 16);
    std.testing.expectEqual(range.elementCount(), 30);
}

test "Data2D data pointer" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);
    const pointer = range.dataPointer(4, 3);
    pointer.* = 10;
    std.testing.expectEqual(data[4 + 8 * 3], 10);
}

test "Data2D get element" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);
    const element = range.getElement(4, 3);
    element.* = 10;
    std.testing.expectEqual(data[4 + 8 * 3], 10);
}

test "Data2D sub range" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);
    var subRange = range.subRange(2, 1, 3, 2);
    std.testing.expectEqual(subRange.dataPointer(0, 0), range.dataPointer(2, 1));
    std.testing.expectEqual(subRange.column_count, 3);
    std.testing.expectEqual(subRange.row_count, 2);
    std.testing.expectEqual(subRange.row_byte_pitch, range.row_byte_pitch);
    std.testing.expectEqual(subRange.elementCount(), 6);
}

test "Data2D get row" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);
    const row = range.getRow(2);
    std.testing.expectEqual(@as(usize, 6), row.len);
    for (row) |*e, i| {
        e.* = @intToFloat(f32, i);
    }
    std.testing.expectEqual(range.getRow(2), data[8 * 2 .. 8 * 2 + 6]);
}

test "rowIterator should iterate over all rows" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);

    var it = range.rowIterator();
    var row_index: usize = 0;
    while (it.next()) |row| : (row_index += 1) {
        std.testing.expectEqual(range.getRow(row_index), row);
    }
    std.testing.expectEqual(range.row_count, row_index);
}

test "elementIterator should iterate over all elements" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromBytes(mem.sliceAsBytes(data[0..]), 6, 5, 32);
    var rowit = range.rowIterator();
    var row_index: usize = 0;
    while (rowit.next()) |row| : (row_index += 1) {
        for (row) |*e, i| {
            e.* = @intToFloat(f32, row_index * 10 + i);
        }
    }

    var elemit = range.elementIterator();
    var element_count: usize = 0;
    while (elemit.next()) |e| : (element_count += 1) {
        std.testing.expectEqual(@intToFloat(f32, element_count % range.column_count + ((element_count / range.column_count) * 10)), e.*);
    }
}

test "setAll should fill all values" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromSlice(&data, 10, 4);
    range.setAll(1);
    var it = range.elementIterator();
    while (it.next()) |e| {
        std.testing.expectEqual(@as(f32, 1), e.*);
    }
}

test "Can make it point to const data" {
    const data: [40]f32 = undefined;
    var range = Data2D(*const f32).fromSlice(&data, 10, 4);
}

test "Copy copyContentFrom" {
    var data: [40]f32 = undefined;
    var range = Data2D(*f32).fromSlice(&data, 10, 4);
    range.copyContentFrom(range.toConst());
}
