const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const BipartiteBuffer = struct {
    memory: []u8,
    primary: []u8,
    secondary_size: usize,
    reserved: []u8,
    reading_size: usize,

    const Self = @This();

    pub fn init(buffer: []u8) Self {
        var self = Self{
            .memory = buffer,
            .primary = undefined,
            .secondary_size = 0,
            .reserved = &[_]u8{},
            .reading_size = 0,
        };
        self.primary.ptr = self.memory.ptr;
        self.primary.len = 0;
        return self;
    }

    pub fn size(self: Self) usize {
        return self.primaryDataSize() + self.secondaryDataSize();
    }

    pub fn empty(self: Self) bool {
        return self.primaryDataSize() == 0;
    }

    pub fn capacity(self: Self) usize {
        return self.memory.len;
    }

    pub fn isFull(self: Self) bool {
        return self.primaryDataSize() > 0 and self.secondaryDataSize() == self.primaryDataStart();
    }

    pub fn reserve(self: *Self, count: usize) ![]u8 {
        if ((self.secondaryDataSize() == 0) and self.hasPrimaryExcessCapacity(count)) {
            self.reserved = self.memory[self.primaryDataEnd()..];
        } else if (self.hasSecondaryExcessCapacity(count)) {
            self.reserved = self.memory[self.secondaryDataSize()..self.primaryDataStart()];
        } else {
            self.reserved = &[_]u8{};
            return error.NotEnoughContigousCapacityAvailable;
        }
        return self.reserved;
    }

    pub fn commit(self: *Self, count: usize) void {
        std.debug.assert(count <= self.reserved.len);
        if (self.reserved.ptr == self.primary.ptr + self.primary.len) {
            self.primary = self.memory[self.primaryDataStart() .. self.primaryDataEnd() + count];
        } else {
            std.debug.assert(self.memory.ptr + self.secondaryDataSize() == self.reserved.ptr);
            self.secondary_size += count;
        }
        self.reserved = &[_]u8{};
    }

    pub fn read(self: Self) []const u8 {
        return self.primaryDataSlice();
    }

    pub fn discard(self: *Self, count_in: usize) void {
        std.debug.assert(self.size() >= count_in);
        var count = count_in;
        if (count >= self.primaryDataSize()) {
            count -= self.primaryDataSize();
            self.primary = self.secondaryDataSlice();
            self.secondary_size = 0;
        }
        self.primary = self.primary[count..];
    }

    pub fn discardAll(self: *Self) void {
        if (self.reserved.len == 0) {
            self.primary.ptr = self.memory.ptr;
            self.primary.len = 0;
        } else {
            self.primary.ptr = self.reserved.ptr;
            self.primary.len = 0;
        }
        self.secondary_size = 0;
    }

    // helper functions

    fn secondaryDataSlice(self: Self) []u8 {
        return self.memory[0..self.secondary_size];
    }

    fn primaryDataSlice(self: Self) []u8 {
        return self.primary;
    }

    fn primaryDataSize(self: Self) usize {
        return self.primary.len;
    }

    fn primaryDataStart(self: Self) usize {
        return @ptrToInt(self.primary.ptr) - @ptrToInt(self.memory.ptr);
    }

    fn primaryDataEnd(self: Self) usize {
        return self.primaryDataSize() + self.primaryDataStart();
    }

    fn secondaryDataSize(self: Self) usize {
        return self.secondary_size;
    }

    fn hasPrimaryExcessCapacity(self: Self, count: usize) bool {
        return self.primaryDataEnd() + count <= self.memory.len;
    }

    fn hasSecondaryExcessCapacity(self: Self, count: usize) bool {
        return self.secondary_size + count <= self.primaryDataStart();
    }
};

test "initialized BipartiteBuffer state" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    testing.expect(buffer.empty());
    testing.expect(!buffer.isFull());
    testing.expectEqual(buffer.size(), 0);
    testing.expectEqual(buffer.capacity(), memory.len);
    testing.expectEqual(buffer.reserved.len, 0);
    testing.expectEqual(buffer.read().len, 0);
}

test "reserving space should return at least that amount of memory if available" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    const reserved = try buffer.reserve(20);
    std.testing.expect(reserved.len >= 20);
    std.testing.expectEqual(reserved, buffer.reserved);
}

test "committing should increase the size and reset the reserved space" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    _ = try buffer.reserve(20);
    buffer.commit(20);

    std.testing.expectEqual(@as(usize, 20), buffer.size());
    std.testing.expectEqual(@as([]u8, &[0]u8{}), buffer.reserved);
}

test "discarding should decrease the size" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    _ = try buffer.reserve(50);
    buffer.commit(50);
    buffer.discard(20);
    std.testing.expectEqual(@as(usize, 30), buffer.size());
}

test "reserving and committing should be possible after using all space and discarding some" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    _ = try buffer.reserve(memory.len);
    buffer.commit(memory.len);
    buffer.discard(40);
    _ = try buffer.reserve(40);
    buffer.commit(40);
    std.testing.expectEqual(memory.len, buffer.size());
    std.testing.expectEqual(memory.len - 40, buffer.read().len);
}

test "committing data and reading it returns the same data, also after discard some" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    const data = "hello this is a test";
    var reserved = try buffer.reserve(data.len);
    std.mem.copy(u8, reserved[0..data.len], data);
    buffer.commit(data.len);
    std.testing.expectEqualStrings(data, buffer.read());
    buffer.discard(5);
    std.testing.expectEqualStrings(data[5..], buffer.read());
}

test "committing data and reading it returns the same data, after already committing almost the whole buffer space" {
    var memory: [100]u8 = undefined;
    var buffer = BipartiteBuffer.init(&memory);

    const data = "hello this is a test";
    _ = try buffer.reserve(memory.len - data.len / 2);
    buffer.commit(memory.len - data.len / 2);
    buffer.discard(data.len);

    var reserved = try buffer.reserve(data.len);
    std.mem.copy(u8, reserved[0..data.len], data);
    buffer.commit(data.len);
    buffer.discard(memory.len - data.len - data.len / 2);
    std.testing.expectEqualStrings(data, buffer.read());
}
