const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn BipartiteBuffer() type {
    return struct {
        memory: []u8,
        primary: []u8,
        secondary_size: usize,
        reserved: []u8,
        reading_size: usize,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator, start_capacity: usize) !Self {
            var self = Self{
                .memory = try allocator.alloc(u8, start_capacity),
                .primary = undefined,
                .secondary_size = 0,
                .reserved = &[_]u8{},
                .reading_size = 0,
                .allocator = allocator,
            };
            self.primary = self.memory[0..0];
            return self;
        }

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.memory);
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
                return BufferReserveError.NotEnoughContigousCapacityAvailable;
            }
            return self.reserved;
        }

        pub fn commit(self: *Self, count: usize) !void {
            if (count > self.reserved.len) return BufferCommitError.CommittingMoreThanReserved;
            if (self.reserved.ptr == self.primary.ptr + self.primary.len) {
                self.primary = self.memory[self.primaryDataStart() .. self.primaryDataEnd() + count];
            } else {
                std.debug.assert(self.memory.ptr + self.secondaryDataSize() == self.reserved.ptr);
                self.secondary_size += count;
            }
            self.reserved = &[_]u8{};
        }

        pub fn peek(self: Self) []const u8 {
            return self.primaryDataSlice();
        }

        pub fn readBlock(self: *Self) []const u8 {
            const data = self.primaryDataSlice();
            self.reading_size = data.len;
            return data;
        }

        pub fn release(self: *Self, count: usize) !void {
            if (count > self.reading_size) return BufferReleaseError.ReleasingMoreThanRead;
            self.discard(count) catch unreachable;
            self.reading_size = 0;
        }

        pub fn discard(self: *Self, count_in: usize) !void {
            if (self.size() < count_in) return BufferDiscardError.DiscardingMoreThanAvailable;
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
                self.primary = self.memory[0..0];
            } else {
                self.primary = self.reserved[0..0];
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
}

const BufferReserveError = error{NotEnoughContigousCapacityAvailable};

const BufferCommitError = error{CommittingMoreThanReserved};

const BufferReleaseError = error{ReleasingMoreThanRead};

const BufferDiscardError = error{DiscardingMoreThanAvailable};

test "initialized BipartiteBuffer state" {
    const capacity = 100;
    var buffer = try BipartiteBuffer().init(testing.allocator, capacity);
    defer buffer.deinit();

    testing.expect(buffer.empty());
    testing.expect(!buffer.isFull());
    testing.expectEqual(buffer.size(), 0);
    testing.expectEqual(buffer.capacity(), capacity);
    testing.expectEqual(buffer.reserved.len, 0);
    testing.expectEqual(buffer.peek().len, 0);
    testing.expectEqual(buffer.readBlock().len, 0);
}

const TestMessage = packed struct {
    f: f32,
    i: i16,
};

fn createTestMessages(comptime message_count: usize) [message_count]TestMessage {
    comptime var test_message_value: TestMessage = undefined;
    test_message_value.f = 10;
    test_message_value.i = 100;
    var test_messages: [message_count]TestMessage = [_]TestMessage{test_message_value} ** message_count;
    for (test_messages) |*test_message, i| {
        test_message.f += @intToFloat(f32, i);
        test_message.i += @intCast(i16, i);
    }
    return test_messages;
}

fn asByteSlice(comptime T: type, x: *const T) []const u8 {
    return std.mem.sliceAsBytes(@ptrCast([*]const T, x)[0..1]);
}

test "push pull messages" {
    var buffer = try BipartiteBuffer().init(testing.allocator, 100);
    defer buffer.deinit();

    var i: u8 = 0;
    while (i < 10) {
        i += 1;
        var message = try buffer.reserve(10);
        for (message[0..10]) |*e, j| {
            e.* = @intCast(u8, j + i * 10);
        }
        try buffer.commit(10);
    }
    i = 0;
    while (i < 10) {
        const peek = buffer.peek();
        testing.expectEqual(@as(usize, (10 - i) * 10), peek.len);
        i += 1;
        for (peek) |e, j| {
            testing.expectEqual(e, @intCast(u8, j + i * 10));
        }
        const read = buffer.readBlock();
        for (read) |e, j| {
            testing.expectEqual(e, @intCast(u8, j + i * 10));
        }
        try buffer.release(10);
    }
}

test "fill and drain BipartiteBuffer" {
    comptime const message_count = 10;
    const test_messages = createTestMessages(message_count);
    const message_size = @sizeOf(TestMessage);
    const extra_capacity = 3;
    var buffer = try BipartiteBuffer().init(testing.allocator, (message_count / 2) * message_size + extra_capacity);
    defer buffer.deinit();

    // first put a few messages in
    for (test_messages[0 .. message_count / 4]) |test_message, i| {
        var reserved = try buffer.reserve(message_size);
        testing.expect(reserved.len >= message_size);
        testing.expect(reserved.ptr == buffer.reserved.ptr);
        testing.expectEqual(reserved.len, buffer.reserved.len);
        std.mem.copy(u8, reserved[0..message_size], asByteSlice(TestMessage, &test_message));
        try buffer.commit(message_size);
        testing.expectEqual(buffer.size(), message_size * (i + 1));
    }
    // then put and pull out at the same time
    for (test_messages[message_count / 4 ..]) |test_message, i| {
        var reserved = try buffer.reserve(message_size);
        testing.expect(reserved.len >= message_size);
        testing.expect(reserved.ptr == buffer.reserved.ptr);
        testing.expectEqual(reserved.len, buffer.reserved.len);
        std.mem.copy(u8, reserved[0..message_size], asByteSlice(TestMessage, &test_message));
        try buffer.commit(message_size);
        testing.expectEqual(buffer.size(), message_size * (message_count / 4 + 1));

        var peek = buffer.peek();
        testing.expect(peek.len >= message_size);
        testing.expectEqualSlices(u8, peek[0..message_size], asByteSlice(TestMessage, &test_messages[i]));
        var block = buffer.readBlock();
        testing.expect(block.len >= message_size);
        testing.expectEqualSlices(u8, block[0..message_size], asByteSlice(TestMessage, &test_messages[i]));
        try buffer.release(message_size);
        testing.expectEqual(buffer.size(), message_size * (message_count / 4));
    }
    // then pull out the last messages
    for (test_messages[message_count - message_count / 4 ..]) |test_message, i| {
        var peek = buffer.peek();
        testing.expect(peek.len >= message_size);
        testing.expectEqualSlices(u8, peek[0..message_size], asByteSlice(TestMessage, &test_message));
        var block = buffer.readBlock();
        testing.expect(block.len >= message_size);
        testing.expectEqualSlices(u8, block[0..message_size], asByteSlice(TestMessage, &test_message));
        try buffer.release(message_size);
        testing.expectEqual(buffer.size(), message_size * (message_count / 4 - i - 1));
    }
    testing.expect(buffer.empty());
    testing.expectEqual(buffer.size(), 0);
}

test "discard data" {
    var buffer = try BipartiteBuffer().init(testing.allocator, 100);
    defer buffer.deinit();

    _ = try buffer.reserve(50);
    try buffer.commit(50);
    testing.expectEqual(buffer.size(), 50);
    try buffer.discard(30);
    testing.expectEqual(buffer.size(), 20);
    buffer.discard(30) catch |err| testing.expectEqual(err, BufferDiscardError.DiscardingMoreThanAvailable);
    testing.expect(!buffer.empty());
    buffer.discardAll();
    testing.expect(buffer.empty());
}

test "release data" {
    var buffer = try BipartiteBuffer().init(testing.allocator, 100);
    defer buffer.deinit();

    _ = try buffer.reserve(50);
    try buffer.commit(50);
    testing.expectEqual(buffer.size(), 50);
    testing.expectError(BufferReleaseError.ReleasingMoreThanRead, buffer.release(30));
    _ = buffer.readBlock();
    try buffer.release(30);
    testing.expectEqual(buffer.size(), 20);
}
