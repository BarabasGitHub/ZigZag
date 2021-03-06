const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

fn alignPointerOffset(comptime Type: type, p: [*]u8) usize {
    return std.mem.alignForward(@ptrToInt(p), @alignOf(Type)) - @ptrToInt(p);
}

fn fieldType(comptime fields: []const StructureOfArraysDescription.FieldDescription, comptime name: []const u8) type {
    return fields[fieldIndex(fields, name)].field_type;
}

fn fieldIndex(comptime fields: []const StructureOfArraysDescription.FieldDescription, comptime name: []const u8) comptime_int {
    for (fields) |field, i| {
        if (std.mem.eql(u8, field.name, name)) return i;
    }
    @compileError("Has no field '" ++ name ++ "'");
}

fn totalSize(comptime fields: []const StructureOfArraysDescription.FieldDescription) comptime_int {
    var size = 0;
    for (fields) |field| {
        size += @sizeOf(field.field_type);
    }
    return size;
}

fn sumOfAlignments(comptime fields: []const StructureOfArraysDescription.FieldDescription) comptime_int {
    var sum = 0;
    for (fields) |field| {
        sum += @alignOf(field.field_type);
    }
    return sum;
}

fn lessThanForStructFieldAlignment(_: void, comptime a: StructureOfArraysDescription.FieldDescription, comptime b: StructureOfArraysDescription.FieldDescription) bool {
    return @alignOf(a.field_type) < @alignOf(b.field_type);
}

fn maximumAlignment(comptime fields: []const StructureOfArraysDescription.FieldDescription) comptime_int {
    return @alignOf(std.sort.max(StructureOfArraysDescription.FieldDescription, fields, {}, lessThanForStructFieldAlignment).?.field_type);
}

fn minimumAlignment(comptime fields: []const StructureOfArraysDescription.FieldDescription) comptime_int {
    return @alignOf(std.sort.min(StructureOfArraysDescription.FieldDescription, fields, {}, lessThanForStructFieldAlignment).?.field_type);
}

fn roundIntegerUp(i: usize, comptime r: usize) usize {
    return ((i + r - 1) / r) * r;
}

pub fn StructureOfArrays(comptime Structure: type) type {
    var descriptions: [std.meta.fields(Structure).len]StructureOfArraysDescription.FieldDescription = undefined;
    for (std.meta.fields(Structure)) |field, i| {
        descriptions[i].field_type = field.field_type;
        descriptions[i].name = field.name;
        descriptions[i].offset = @byteOffsetOf(Structure, field.name);
    }
    return StructureOfArraysAdvanced(.{ .input_struct = Structure, .fields = &descriptions });
}

pub const StructureOfArraysDescription = struct {
    pub const FieldDescription = struct {
        field_type: type,
        name: []const u8,
        offset: usize,
    };
    input_struct: type,
    fields: []const FieldDescription,
};

pub fn StructureOfArraysAdvanced(comptime description: StructureOfArraysDescription) type {
    return struct {
        const Structure = description.input_struct;
        const fields = description.fields;
        const maximum_alignment = maximumAlignment(fields);
        const minimum_alignment = minimumAlignment(fields);
        const total_size_fields = totalSize(fields);

        storage: []align(maximum_alignment) u8,
        len: usize,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            // debug.warn("Max alignement is {}\n", .{maximum_alignment});
            // debug.warn("Min alignement is {}\n", .{minimum_alignment});
            // debug.warn("Total size is {}\n", .{total_size_fields});
            return .{
                .storage = &[_]u8{},
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn initWithCapacity(allocator: *Allocator, requested_capacity: usize) !Self {
            return Self{
                .storage = try allocator.alignedAlloc(u8, maximum_alignment, roundIntegerUp(requested_capacity, maximum_alignment / minimum_alignment) * total_size_fields),
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.storage);
        }

        pub fn empty(self: Self) bool {
            return self.len == 0;
        }

        pub fn size(self: Self) usize {
            return self.len;
        }

        pub fn capacity(self: Self) usize {
            return self.storage.len / total_size_fields;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn append(self: *Self, values: Structure) !void {
            try self.ensureCapacity(self.len + 1);
            self.appendAssumeCapacity(values);
        }

        pub fn appendAssumeCapacity(self: *Self, values: Structure) void {
            std.debug.assert(self.capacity() > self.len);
            const old_size = self.len;
            self.len = old_size + 1;
            self.setStructure(old_size, values);
        }

        pub fn growCapacity(self: *Self, amount: usize) !void {
            const old_capacity = self.capacity();
            const new_capacity = old_capacity + std.math.max(old_capacity / 2, amount);
            try self.setCapacity(new_capacity);
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            if (new_capacity > self.capacity()) {
                try self.growCapacity(new_capacity - self.capacity());
            }
        }

        /// Rounds up the `new_capacity` for alignment purposes
        pub fn setCapacity(self: *Self, requested_capacity: usize) !void {
            var temp = try Self.initWithCapacity(self.allocator, requested_capacity);
            temp.copyFromAssumingCapacity(self.*);
            self.deinit();
            self.storage = temp.storage;
        }

        fn copyFromAssumingCapacity(self: *Self, other: Self) void {
            self.len = other.len;
            inline for (fields) |field| {
                std.mem.copy(field.field_type, self.span(field.name), other.span(field.name));
            }
        }

        pub fn span(self: Self, comptime field_name: []const u8) []fieldType(fields, field_name) {
            comptime const FieldType = fieldType(fields, field_name);
            comptime const field_index = fieldIndex(fields, field_name);
            comptime const fields_size = totalSize(fields[0..field_index]);
            const start_offset = fields_size * self.capacity();
            return std.mem.bytesAsSlice(FieldType, @alignCast(@alignOf(FieldType), self.storage[start_offset .. start_offset + self.len * @sizeOf(FieldType)]));
        }

        pub fn at(self: Self, comptime field_name: []const u8, index: usize) fieldType(fields, field_name) {
            return self.span(field_name)[index];
        }

        pub fn set(self: Self, comptime field_name: []const u8, index: usize, value: fieldType(fields, field_name)) void {
            self.span(field_name)[index] = value;
        }

        pub fn setStructure(self: Self, index: usize, values: Structure) void {
            const value_bytes = std.mem.asBytes(&values);
            inline for (fields) |field| {
                self.set(field.name, index, std.mem.bytesToValue(field.field_type, value_bytes[field.offset .. field.offset + @sizeOf(field.field_type)]));
            }
        }

        pub fn popBack(self: *Self) void {
            self.len -= 1;
        }
    };
}

const TestStruct = struct {
    a: u16,
    b: f64,
    c: i128,
};

const test_values = [_]TestStruct{
    .{ .a = 0, .b = 1.0, .c = 1 },
    .{ .a = 1, .b = 2.0, .c = 3 },
    .{ .a = 2, .b = 3.0, .c = 4 },
    .{ .a = 3, .b = 4.0, .c = 5 },
};

test "StructureOfArrays initialization" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    testing.expect(container.empty());
    testing.expectEqual(@as(usize, 0), container.capacity());
}

test "StructureOfArrays initialization with capacity" {
    var container = try StructureOfArrays(TestStruct).initWithCapacity(testing.allocator, 32);
    defer container.deinit();

    testing.expect(container.empty());
    testing.expectEqual(@as(usize, 32), container.capacity());
}

test "StructureOfArrays append elements" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val, i| {
        const size = i + 1;
        try container.append(val);
        testing.expect(!container.empty());
        testing.expectEqual(@as(usize, size), container.size());
        testing.expect(container.capacity() >= size);
    }
}

test "StructureOfArrays clear" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val| {
        try container.append(val);
    }

    container.clear();

    testing.expectEqual(@as(usize, 0), container.size());
    testing.expect(container.empty());
}

test "StructureOfArrays set capacity" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();
    try container.setCapacity(10);
    testing.expect(container.capacity() >= 10);
    const new_capacity: usize = 10 * @TypeOf(container).maximum_alignment / @TypeOf(container).minimum_alignment;
    try container.setCapacity(new_capacity);
    testing.expectEqual(new_capacity, container.capacity());
}

test "StructureOfArrays grow capacity increases the capacity" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();
    for ([_]usize{ 1, 10, 1 }) |val| {
        const old_capacity = container.capacity();
        try container.growCapacity(val);
        testing.expect(container.capacity() >= old_capacity + val);
    }
}

test "StructureOfArrays grow capacity maintains the values in the container" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val| {
        try container.append(val);
    }

    try container.growCapacity(100);

    for (test_values) |val, i| {
        testing.expectEqual(val.a, container.at("a", i));
        testing.expectEqual(val.b, container.at("b", i));
        testing.expectEqual(val.c, container.at("c", i));
    }
}

test "StructureOfArrays ensure capacity" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();
    try container.ensureCapacity(10);
    testing.expect(container.capacity() >= 10);
    try container.ensureCapacity(0);
    testing.expect(container.capacity() >= 10);
    try container.ensureCapacity(20);
    testing.expect(container.capacity() >= 20);
}

test "StructureOfArrays get slice of field" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val| {
        try container.append(val);
    }

    testing.expectEqual(test_values.len, container.span("a").len);
    testing.expectEqual(test_values.len, container.span("b").len);
    testing.expectEqual(test_values.len, container.span("c").len);

    for (test_values) |val, i| {
        testing.expectEqual(val.a, container.span("a")[i]);
        testing.expectEqual(val.b, container.span("b")[i]);
        testing.expectEqual(val.c, container.span("c")[i]);
    }
}

test "StructureOfArrays at" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val| {
        try container.append(val);
    }

    for (test_values) |val, i| {
        testing.expectEqual(val.a, container.at("a", i));
        testing.expectEqual(val.b, container.at("b", i));
        testing.expectEqual(val.c, container.at("c", i));
    }
}

test "StructureOfArrays don't grow capacity if not needed" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    try container.setCapacity(16);
    const old_capacity = container.capacity();
    for (test_values) |val| {
        try container.append(val);
    }

    testing.expectEqual(old_capacity, container.capacity());
}

test "StructureOfArrays pop back" {
    var container = StructureOfArrays(TestStruct).init(testing.allocator);
    defer container.deinit();

    for (test_values) |val| {
        try container.append(val);
    }

    container.popBack();
    testing.expectEqual(test_values.len - 1, container.size());
    for (test_values[0 .. test_values.len - 1]) |val, i| {
        testing.expectEqual(val.a, container.at("a", i));
        testing.expectEqual(val.b, container.at("b", i));
        testing.expectEqual(val.c, container.at("c", i));
    }
}
