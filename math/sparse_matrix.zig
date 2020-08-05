const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn SparseMatrix(comptime DataType: type) type {
    return struct {
        allocator: *Allocator,
        values: ArrayListUnmanaged(DataType),
        column_indices: ArrayListUnmanaged(u32),
        // indices to the column indices and values, start and end
        row_offsets: ArrayListUnmanaged(u32),
        column_count: u32,
        sorted: bool, // indicates whether this matrix is in sorted form or not

        const Self = @This();

        pub fn init(allocator: *Allocator, rows: u32, columns: u32, elements: u32) !Self {
            var self = Self{
                .allocator = allocator,
                .values = ArrayListUnmanaged(DataType){},
                .column_indices = ArrayListUnmanaged(u32){},
                .row_offsets = ArrayListUnmanaged(u32){},
                .column_count = columns,
                .sorted = true,
            };
            errdefer self.deinit();
            try self.values.resize(self.allocator, elements);
            try self.column_indices.resize(self.allocator, elements);
            try self.row_offsets.resize(self.allocator, rows + 1);
            std.mem.set(u32, self.row_offsets.items, 0);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.values.deinit(self.allocator);
            self.column_indices.deinit(self.allocator);
            self.row_offsets.deinit(self.allocator);
        }

        pub fn numberOfRows(self: Self) u32 {
            return @intCast(u32, self.row_offsets.items.len - 1);
        }

        pub fn numberOfColumns(self: Self) u32 {
            return self.column_count;
        }

        pub fn numberOfElements(self: Self) u32 {
            return @intCast(u32, self.column_indices.items.len);
        }

        pub fn clear(self: *Self) void {
            self.values.resize(self.allocator, 0) catch unreachable;
            self.column_indices.resize(self.allocator, 0) catch unreachable;
            std.mem.set(u32, self.row_offsets.items, 0);
            self.sorted = true;
        }

        pub fn sparsityRatio(self: Self) f32 {
            return @intToFloat(f32, self.numberOfElements()) / @intToFloat(f32, self.numberOfColumns() * self.numberOfRows());
        }

        pub fn densityRatio(self: Self) f32 {
            return @intToFloat(f32, self.numberOfColumns() * self.numberOfRows()) / @intToFloat(f32, self.numberOfElements());
        }

        pub fn columnsInRow(self: Self, row: u32) []u32 {
            const offset_start = self.row_offsets.items[row];
            const offset_end = self.row_offsets.items[row + 1];
            return self.column_indices.items[offset_start..offset_end];
        }

        pub fn valuesInRow(self: Self, row: u32) []DataType {
            const offset_start = self.row_offsets.items[row];
            const offset_end = self.row_offsets.items[row + 1];
            return self.values.items[offset_start..offset_end];
        }

        fn elementIndex(self: Self, row: u32, column: u32) u32 {
            return for (self.columnsInRow(row)) |c, i| {
                if (c == column) break @intCast(u32, i + self.row_offsets.items[row]);
            } else unreachable;
        }

        pub fn getElement(self: Self, row: u32, column: u32) *DataType {
            return &self.values.items[self.elementIndex(row, column)];
        }

        pub fn addElement(self: *Self, row: u32, column: u32, value: DataType) !void {
            const index = self.row_offsets.items[row + 1];
            try self.column_indices.insert(self.allocator, index, column);
            try self.values.insert(self.allocator, index, value);
            for (self.row_offsets.items[row + 1 ..]) |*offset| {
                offset.* += 1;
            }
            self.sorted = index > self.row_offsets.items[row] and self.column_indices.items[index - 1] < self.column_indices.items[index];
        }

        pub fn removeZeroEntries(self: *Self) void {
            var removedCount: u32 = 0;
            for (self.row_offsets.items[1..]) |end, i| {
                const start = self.row_offsets.items[i];
                self.row_offsets.items[i] = start - removedCount;
                for (self.values.items[start..end]) |v, j| {
                    if (v == 0) {
                        removedCount += 1;
                    } else if (removedCount > 0) {
                        const offset = start + @intCast(u32, j);
                        self.values.items[offset - removedCount] = v;
                        self.column_indices.items[offset - removedCount] = self.column_indices.items[offset];
                    }
                }
            }
            const value_count = self.row_offsets.items[self.row_offsets.items.len - 1] - removedCount;
            self.row_offsets.items[self.row_offsets.items.len - 1] = value_count;
            self.values.resize(self.allocator, value_count) catch unreachable;
            self.column_indices.resize(self.allocator, value_count) catch unreachable;
        }

        pub fn transpose(self: Self, transposed: *Self) !void {
            std.debug.assert(&self != transposed);
            const column_count = self.numberOfColumns();
            transposed.row_offsets.resize(self.allocator, 0) catch unreachable;
            try transposed.row_offsets.resize(transposed.allocator, column_count + 1);
            transposed.clear();
            const row_count = self.numberOfRows();
            transposed.column_count = row_count;
            const element_count = self.numberOfElements();
            try transposed.values.resize(transposed.allocator, element_count);
            try transposed.column_indices.resize(transposed.allocator, element_count);

            // count the number of elements in columns and store them in the output row indices
            const column_counts = transposed.row_offsets.items[1..];
            for (self.column_indices.items) |column| {
                column_counts[column] += 1;
            }

            // set the row offsets to point at the first element of the all elements for each row
            // note: we also displace all offsets, such that they are all at their final position
            {
                var total_offset: u32 = 0;
                for (column_counts) |*offset| {
                    const t = offset.*;
                    offset.* = total_offset;
                    total_offset += t;
                }
            }

            // copy the values and assign the right column indices, meanwhile keeping track of where to add the new elements
            // in the row offsets
            var old_row: u32 = 0;
            while (old_row < row_count) : (old_row += 1) {
                const values = self.valuesInRow(old_row);
                for (self.columnsInRow(old_row)) |column, i| {
                    const current_column_count = &column_counts[column];
                    const destination_index = current_column_count.*;
                    current_column_count.* += 1;
                    transposed.column_indices.items[destination_index] = old_row;
                    transposed.values.items[destination_index] = values[i];
                }
            }
            transposed.sorted = true;
        }

        /// The multiplication algorithm doesn't produce a sorted matrix.
        /// The Allocator is needed to allocate workspace for the multiplication and
        /// will be two arrays of b.numberOfColumns(), one of DataType and one of u32.
        pub fn multiply(a: Self, b: Self, c: *Self, workspace_allocator: *Allocator) !void {
            std.debug.assert(a.numberOfColumns() == b.numberOfRows());
            const column_count_b = b.numberOfColumns();
            const workspace = try workspace_allocator.alloc(DataType, column_count_b);
            defer workspace_allocator.free(workspace);
            const used = try workspace_allocator.alloc(u32, column_count_b);
            defer workspace_allocator.free(used);

            c.row_offsets.resize(c.allocator, 0) catch unreachable;
            try c.row_offsets.resize(c.allocator, a.row_offsets.items.len);
            c.column_count = column_count_b;
            c.column_indices.resize(c.allocator, 0) catch unreachable;
            c.values.resize(c.allocator, 0) catch unreachable;

            const maximum_elements = @intToFloat(f32, c.numberOfRows()) * @intToFloat(f32, c.numberOfColumns());
            // reserve the amount for our first guess
            try c.column_indices.ensureCapacity(c.allocator, a.numberOfElements() + b.numberOfElements());
            // set our first estimate to whatever we have room for
            var sparsity_estimate = @intToFloat(f32, c.column_indices.capacity) / maximum_elements;
            std.mem.set(u32, used, 0);

            const row_count_a = a.numberOfRows();
            var row_a: u32 = 0;
            while (row_a < row_count_a) : (row_a += 1) {
                const row_c = row_a;
                c.row_offsets.items[row_c] = @intCast(u32, c.column_indices.items.len);

                const used_mark = row_a + 1;

                const index_a_end = a.row_offsets.items[row_a + 1];
                var index_a = a.row_offsets.items[row_a];
                while (index_a < index_a_end) : (index_a += 1) {
                    const column_a = a.column_indices.items[index_a];
                    const value_a = a.values.items[index_a];

                    const row_b = column_a;
                    // scatter
                    const index_b_end = b.row_offsets.items[row_b + 1];
                    var index_b = b.row_offsets.items[row_b];
                    while (index_b < index_b_end) : (index_b += 1) {
                        const column_b = b.column_indices.items[index_b];
                        const value_b = b.values.items[index_b];
                        if (used[column_b] < used_mark) {
                            used[column_b] = used_mark;
                            try c.column_indices.append(c.allocator, column_b);
                            workspace[column_b] = value_b * value_a;
                        } else {
                            workspace[column_b] += value_b * value_a;
                        }
                    }
                }

                try c.values.ensureCapacity(c.allocator, c.column_indices.capacity);

                for (c.column_indices.items[c.row_offsets.items[row_c]..c.column_indices.items.len]) |column_c| {
                    const value_ab = workspace[column_c];
                    c.values.appendAssumeCapacity(value_ab);
                }

                const new_sparsity_estimate = @intToFloat(f32, c.values.items.len) / (@intToFloat(f32, c.numberOfColumns()) * @intToFloat(f32, row_a + 1));
                if (new_sparsity_estimate > sparsity_estimate) {
                    // make room for at least 30% more elements
                    sparsity_estimate = std.math.max(new_sparsity_estimate, 1.3 * sparsity_estimate);
                    // add something to our new capacity such that we can always fill the next column
                    const reserve_size = @floatToInt(usize, std.math.ceil(sparsity_estimate * maximum_elements)) + c.numberOfColumns();
                    try c.column_indices.ensureCapacity(c.allocator, reserve_size);
                }
            }

            c.row_offsets.items[c.row_offsets.items.len - 1] = @intCast(u32, c.column_indices.items.len);
            c.sorted = false;
        }

        pub fn multiplyAdd(self: Self, x: []const DataType, x_scale: DataType, y: []DataType, y_scale: DataType) void {
            debug.assert(self.numberOfColumns() == x.len);
            debug.assert(self.numberOfRows() == y.len);

            for (y) |*element_y, i| {
                const row = @intCast(u32, i);
                var value: DataType = 0;
                const values = self.valuesInRow(row);
                const column_indices = self.columnsInRow(row);
                for (column_indices) |column, index| {
                    const value_m = values[index];
                    const value_x = x[column];
                    value += value_m * value_x;
                }
                value *= x_scale;
                value += element_y.* * y_scale;
                element_y.* = value;
            }
        }

        pub fn multiplyAddTransposed(self: Self, x: []const DataType, x_scale: DataType, y: []DataType, y_scale: DataType) void {
            debug.assert(self.numberOfRows() == x.len);
            debug.assert(self.numberOfColumns() == y.len);

            for (y) |*e| {
                e.* *= y_scale;
            }

            for (x) |element_x, i| {
                const row = @intCast(u32, i);
                const value_x = element_x * x_scale;
                const values = self.valuesInRow(row);
                const column_indices = self.columnsInRow(row);
                for (column_indices) |column, index| {
                    const value_m = values[index];
                    const value_mx = value_m * value_x;
                    y[column] += value_mx;
                }
            }
        }
    };
}

// Doesn't really work correctly, only if both matrices are completely sorted and have no extra elements
fn equal(a: SparseMatrix(f32), b: SparseMatrix(f32)) bool {
    return a.column_count == b.column_count and
        std.mem.eql(f32, a.values.items, b.values.items) and
        std.mem.eql(u32, a.column_indices.items, b.column_indices.items) and
        std.mem.eql(u32, a.row_offsets.items, b.row_offsets.items);
}

test "SparseMatrix init" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 10, 5, 14);
    defer matrix.deinit();

    testing.expectEqual(matrix.numberOfRows(), 10);
    testing.expectEqual(matrix.numberOfColumns(), 5);
    testing.expectEqual(matrix.numberOfElements(), 14);
}

test "SparseMatrix sparsityRatio and densityRatio" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 10, 5, 14);
    defer matrix.deinit();

    testing.expectEqual(matrix.densityRatio(), 50.0 / 14.0);
    testing.expectEqual(matrix.sparsityRatio(), 14.0 / 50.0);
}

test "SparseMatrix columnsInRow and valuesInRow" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 10, 14);
    defer matrix.deinit();

    for (matrix.values.items) |*v, i| {
        v.* = @intToFloat(f32, i);
    }

    for (matrix.column_indices.items) |*c, i| {
        c.* = (@intCast(u32, i) * 3) % 10;
    }

    var offset: u32 = 0;
    for (matrix.row_offsets.items) |*o| {
        o.* = offset;
        offset = std.math.min(offset + 3, 14);
    }

    testing.expectEqual(matrix.valuesInRow(0).len, 3);
    testing.expectEqual(matrix.valuesInRow(0)[0], 0);
    testing.expectEqual(matrix.valuesInRow(0)[1], 1);
    testing.expectEqual(matrix.valuesInRow(0)[2], 2);
    testing.expectEqual(matrix.valuesInRow(1).len, 3);
    testing.expectEqual(matrix.valuesInRow(1)[0], 3);
    testing.expectEqual(matrix.valuesInRow(1)[1], 4);
    testing.expectEqual(matrix.valuesInRow(1)[2], 5);
    testing.expectEqual(matrix.valuesInRow(2).len, 3);
    testing.expectEqual(matrix.valuesInRow(2)[0], 6);
    testing.expectEqual(matrix.valuesInRow(2)[1], 7);
    testing.expectEqual(matrix.valuesInRow(2)[2], 8);
    testing.expectEqual(matrix.valuesInRow(3).len, 3);
    testing.expectEqual(matrix.valuesInRow(3)[0], 9);
    testing.expectEqual(matrix.valuesInRow(3)[1], 10);
    testing.expectEqual(matrix.valuesInRow(3)[2], 11);
    testing.expectEqual(matrix.valuesInRow(4).len, 2);
    testing.expectEqual(matrix.valuesInRow(4)[0], 12);
    testing.expectEqual(matrix.valuesInRow(4)[1], 13);

    testing.expectEqual(matrix.columnsInRow(0).len, 3);
    testing.expectEqual(matrix.columnsInRow(0)[0], 0);
    testing.expectEqual(matrix.columnsInRow(0)[1], 3);
    testing.expectEqual(matrix.columnsInRow(0)[2], 6);
    testing.expectEqual(matrix.columnsInRow(1).len, 3);
    testing.expectEqual(matrix.columnsInRow(1)[0], 9);
    testing.expectEqual(matrix.columnsInRow(1)[1], 2);
    testing.expectEqual(matrix.columnsInRow(1)[2], 5);
    testing.expectEqual(matrix.columnsInRow(2).len, 3);
    testing.expectEqual(matrix.columnsInRow(2)[0], 8);
    testing.expectEqual(matrix.columnsInRow(2)[1], 1);
    testing.expectEqual(matrix.columnsInRow(2)[2], 4);
    testing.expectEqual(matrix.columnsInRow(3).len, 3);
    testing.expectEqual(matrix.columnsInRow(3)[0], 7);
    testing.expectEqual(matrix.columnsInRow(3)[1], 0);
    testing.expectEqual(matrix.columnsInRow(3)[2], 3);
    testing.expectEqual(matrix.columnsInRow(4).len, 2);
    testing.expectEqual(matrix.columnsInRow(4)[0], 6);
    testing.expectEqual(matrix.columnsInRow(4)[1], 9);
}

test "SparseMatrix get element" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 10, 14);
    defer matrix.deinit();

    for (matrix.values.items) |*v, i| {
        v.* = @intToFloat(f32, i);
    }

    for (matrix.column_indices.items) |*c, i| {
        c.* = (@intCast(u32, i) * 3) % 10;
    }

    var offset: u32 = 0;
    for (matrix.row_offsets.items) |*o| {
        o.* = offset;
        offset = std.math.min(offset + 3, 14);
    }

    testing.expectEqual(matrix.getElement(0, 0).*, 0);
    testing.expectEqual(matrix.getElement(0, 3).*, 1);
    testing.expectEqual(matrix.getElement(0, 6).*, 2);
    testing.expectEqual(matrix.getElement(1, 9).*, 3);
    testing.expectEqual(matrix.getElement(1, 2).*, 4);
    testing.expectEqual(matrix.getElement(1, 5).*, 5);
    testing.expectEqual(matrix.getElement(2, 8).*, 6);
    testing.expectEqual(matrix.getElement(2, 1).*, 7);
    testing.expectEqual(matrix.getElement(2, 4).*, 8);
    testing.expectEqual(matrix.getElement(3, 7).*, 9);
    testing.expectEqual(matrix.getElement(3, 0).*, 10);
    testing.expectEqual(matrix.getElement(3, 3).*, 11);
    testing.expectEqual(matrix.getElement(4, 6).*, 12);
    testing.expectEqual(matrix.getElement(4, 9).*, 13);
}

test "SparseMatrix add element" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 10, 0);
    defer matrix.deinit();

    try matrix.addElement(1, 2, 1);
    testing.expectEqual(matrix.getElement(1, 2).*, 1);
    try matrix.addElement(1, 1, 2);
    testing.expectEqual(matrix.getElement(1, 1).*, 2);
    try matrix.addElement(0, 4, 3);
    testing.expectEqual(matrix.getElement(0, 4).*, 3);
    testing.expectEqual(matrix.numberOfElements(), 3);
}

test "SparseMatrix remove zero entries" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 10, 14);
    defer matrix.deinit();

    for (matrix.values.items) |*v, i| {
        v.* = @intToFloat(f32, i % 2);
    }

    for (matrix.column_indices.items) |*c, i| {
        c.* = (@intCast(u32, i) * 3) % 10;
    }

    var offset: u32 = 0;
    for (matrix.row_offsets.items) |*o| {
        o.* = offset;
        offset = std.math.min(offset + 3, 14);
    }

    matrix.removeZeroEntries();
    testing.expectEqual(matrix.numberOfElements(), 7);
}

test "SparseMatrix transpose" {
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 10, 14);
    defer matrix.deinit();

    for (matrix.values.items) |*v, i| {
        v.* = @intToFloat(f32, i);
    }

    for (matrix.column_indices.items) |*c, i| {
        c.* = (@intCast(u32, i) * 3) % 10;
    }

    var offset: u32 = 0;
    for (matrix.row_offsets.items) |*o| {
        o.* = offset;
        offset = std.math.min(offset + 3, 14);
    }

    var matrix_transposed = try SparseMatrix(f32).init(testing.allocator, 5, 10, 14);
    defer matrix_transposed.deinit();

    try matrix.transpose(&matrix_transposed);

    testing.expectEqual(matrix_transposed.getElement(0, 0).*, 0);
    testing.expectEqual(matrix_transposed.getElement(3, 0).*, 1);
    testing.expectEqual(matrix_transposed.getElement(6, 0).*, 2);
    testing.expectEqual(matrix_transposed.getElement(9, 1).*, 3);
    testing.expectEqual(matrix_transposed.getElement(2, 1).*, 4);
    testing.expectEqual(matrix_transposed.getElement(5, 1).*, 5);
    testing.expectEqual(matrix_transposed.getElement(8, 2).*, 6);
    testing.expectEqual(matrix_transposed.getElement(1, 2).*, 7);
    testing.expectEqual(matrix_transposed.getElement(4, 2).*, 8);
    testing.expectEqual(matrix_transposed.getElement(7, 3).*, 9);
    testing.expectEqual(matrix_transposed.getElement(0, 3).*, 10);
    testing.expectEqual(matrix_transposed.getElement(3, 3).*, 11);
    testing.expectEqual(matrix_transposed.getElement(6, 4).*, 12);
    testing.expectEqual(matrix_transposed.getElement(9, 4).*, 13);
}

test "SparseMatrix multiply" {
    // 0, 0, 1, 0, 0,
    // 0, 2, 0, 3, 0,
    // 4, 0, 0, 5, 0,
    // 0, 6, 0, 0, 7,
    var matrix_a = try SparseMatrix(f32).init(testing.allocator, 4, 5, 7);
    defer matrix_a.deinit();
    std.mem.copy(u32, matrix_a.column_indices.items, &[_]u32{ 2, 1, 3, 0, 3, 1, 4 });
    std.mem.copy(u32, matrix_a.row_offsets.items, &[_]u32{ 0, 1, 3, 5, 7 });
    std.mem.copy(f32, matrix_a.values.items, &[_]f32{ 1, 2, 3, 4, 5, 6, 7 });

    // 0, 0, 1,
    // 0, 2, 3,
    // 4, 0, 0,
    // 0, 5, 6,
    // 7, 0, 0,

    var matrix_b = try SparseMatrix(f32).init(testing.allocator, 5, 3, 7);
    defer matrix_b.deinit();
    std.mem.copy(u32, matrix_b.column_indices.items, &[_]u32{ 2, 1, 2, 0, 1, 2, 0 });
    std.mem.copy(u32, matrix_b.row_offsets.items, &[_]u32{ 0, 1, 3, 4, 6, 7 });
    std.mem.copy(f32, matrix_b.values.items, &[_]f32{ 1, 2, 3, 4, 5, 6, 7 });

    // 4,   0,  0,
    // 0,  19, 24,
    // 0,  25, 34,
    // 49, 12, 18

    var expected = try SparseMatrix(f32).init(testing.allocator, 4, 3, 8);
    defer expected.deinit();
    std.mem.copy(u32, expected.column_indices.items, &[_]u32{ 0, 1, 2, 1, 2, 0, 1, 2 });
    std.mem.copy(u32, expected.row_offsets.items, &[_]u32{ 0, 1, 3, 5, 8 });
    std.mem.copy(f32, expected.values.items, &[_]f32{ 4, 19, 24, 25, 34, 49, 12, 18 });

    var result = try SparseMatrix(f32).init(testing.allocator, 0, 0, 0);
    defer result.deinit();
    try SparseMatrix(f32).multiply(matrix_a, matrix_b, &result, testing.allocator);

    // do a double transpose to make the result ordered
    var transposed_result = try SparseMatrix(f32).init(testing.allocator, 0, 0, 0);
    defer transposed_result.deinit();
    try result.transpose(&transposed_result);
    try transposed_result.transpose(&result);

    testing.expect(equal(expected, result));
}

test "SparseMatrix multiplyAdd" {
    // 0, 0, 1,
    // 0, 2, 3,
    // 4, 0, 0,
    // 0, 5, 6,
    // 7, 0, 0,
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 3, 7);
    defer matrix.deinit();
    std.mem.copy(u32, matrix.column_indices.items, &[_]u32{ 2, 1, 2, 0, 1, 2, 0 });
    std.mem.copy(u32, matrix.row_offsets.items, &[_]u32{ 0, 1, 3, 4, 6, 7 });
    std.mem.copy(f32, matrix.values.items, &[_]f32{ 1, 2, 3, 4, 5, 6, 7 });

    const x = [_]f32{ 1, 2, 3 };
    var y = [_]f32{ 1, 2, 3, 4, 5 };

    matrix.multiplyAdd(x[0..], 2, y[0..], 3);
    testing.expectEqual(y[0], 6 + 3);
    testing.expectEqual(y[1], 8 + 18 + 6);
    testing.expectEqual(y[2], 8 + 9);
    testing.expectEqual(y[3], 20 + 36 + 12);
    testing.expectEqual(y[4], 14 + 15);
}

test "SparseMatrix multiplyAddTransposed" {
    // 0, 0, 1,
    // 0, 2, 3,
    // 4, 0, 0,
    // 0, 5, 6,
    // 7, 0, 0,
    var matrix = try SparseMatrix(f32).init(testing.allocator, 5, 3, 7);
    defer matrix.deinit();
    std.mem.copy(u32, matrix.column_indices.items, &[_]u32{ 2, 1, 2, 0, 1, 2, 0 });
    std.mem.copy(u32, matrix.row_offsets.items, &[_]u32{ 0, 1, 3, 4, 6, 7 });
    std.mem.copy(f32, matrix.values.items, &[_]f32{ 1, 2, 3, 4, 5, 6, 7 });

    const x = [_]f32{ 1, 2, 3, 4, 5 };
    var y = [_]f32{ 1, 2, 3 };

    matrix.multiplyAddTransposed(x[0..], 2, y[0..], 3);
    testing.expectEqual(y[0], 24 + 70 + 3);
    testing.expectEqual(y[1], 8 + 40 + 6);
    testing.expectEqual(y[2], 2 + 12 + 48 + 9);
}
