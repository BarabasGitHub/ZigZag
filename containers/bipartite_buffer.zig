const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn BipartiteBuffer() type {
    return struct {
        memory : []u8,
        primary : []u8,
        secondary_size : usize,
        reserved : []u8,
        reading_size : usize,
        allocator : *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator, start_capacity : usize) !Self {
            var self = Self{
                .memory = try allocator.alloc(u8, start_capacity),
                .primary = undefined,
                .secondary_size = 0,
                .reserved = []u8{},
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

        pub fn reserve(self: * Self, count: usize) ![]u8 {
            if ((self.secondaryDataSize() == 0) and self.hasPrimaryExcessCapacity(count)){
                self.reserved = self.memory[self.primaryDataEnd()..];
            } else if (self.hasSecondaryExcessCapacity(count)) {
                self.reserved = self.memory[self.secondaryDataSize()..self.primaryDataStart()];
            } else {
                self.reserved = []u8{};
                return BufferReserveError.NotEnoughContigousCapacityAvailable;
            }
            return self.reserved;
        }

        pub fn commit(self: * Self, count: usize) !void {
            if (count > self.reserved.len) return BufferCommitError.CommittingMoreThanReserved;
            if (self.reserved.ptr == self.primary.ptr + self.primary.len) {
                self.primary = self.memory[self.primaryDataStart()..self.primaryDataEnd() + count];
            } else {
                testing.expect(self.memory.ptr + self.secondaryDataSize() == self.reserved.ptr);
                self.secondary_size += count;
            }
            self.reserved = []u8{};
        }

        pub fn peek(self: Self) [] const u8 {
            return self.primaryDataSlice();
        }

        pub fn readBlock(self: * Self) [] const u8 {
            const data = self.primaryDataSlice();
            self.reading_size = data.len;
            return data;
        }

        pub fn release(self: * Self, count: usize) !void {
            if(count > self.reading_size) return BufferReleaseError.ReleasingMoreThanRead;
            self.discard(count) catch unreachable;
            self.reading_size = 0;
        }

        pub fn discard(self: * Self, count_in: usize) !void {
            if (self.size() < count_in) return BufferDiscardError.DiscardingMoreThanAvailable;
            var count = count_in;
            if (count >= self.primaryDataSize()) {
                count -= self.primaryDataSize();
                self.primary = self.secondaryDataSlice();
                self.secondary_size = 0;
            }
            self.primary = self.primary[count..];
        }

        pub fn discardAll(self: * Self) void {
            if (self.reserved.len == 0){
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

const BufferReserveError = error {
    NotEnoughContigousCapacityAvailable,
};

const BufferCommitError = error {
    CommittingMoreThanReserved,
};

const BufferReleaseError = error {
    ReleasingMoreThanRead,
};

const BufferDiscardError = error {
    DiscardingMoreThanAvailable,
};


test "initialized BipartiteBuffer state" {
    const capacity = 100;
    var buffer = try BipartiteBuffer().init(debug.global_allocator, capacity);
    defer buffer.deinit();

    testing.expect(buffer.empty());
    testing.expect(!buffer.isFull());
    testing.expect(buffer.size() == 0);
    testing.expect(buffer.capacity() == capacity);
    testing.expect(buffer.reserved.len == 0);
    testing.expect(buffer.peek().len == 0);
    testing.expect(buffer.readBlock().len == 0);
}

const TestMessage = packed struct {
    f : f32,
    i : i16,
};

fn createTestMessages(comptime message_count : usize) [message_count]TestMessage {
    comptime var test_message_value : TestMessage = undefined;
    test_message_value.f = 10;
    test_message_value.i = 100;
    var test_messages : [message_count]TestMessage = []TestMessage{test_message_value} ** message_count;
    for (test_messages) |*test_message, i|{
        test_message.f += @intToFloat(f32, i);
        test_message.i += @intCast(i16, i);
    }
    return test_messages;
}


fn asByteSlice(x: var) []const u8 {
    const T = @typeOf(x);
    return @sliceToBytes(([]const T{x})[0..1]);
}

test "fill and drain BipartiteBuffer" {
    comptime const message_count = 10;
    const test_messages = createTestMessages(message_count);
    const message_size = @sizeOf(TestMessage);
    const extra_capacity = 3;
    var buffer = try BipartiteBuffer().init(debug.global_allocator, (message_count/2) * message_size + extra_capacity);
    defer buffer.deinit();

    // first put a few messages in
    for (test_messages[0..message_count/4]) |test_message, i| {
        var reserved = try buffer.reserve(message_size);
        testing.expect(reserved.len >= message_size);
        testing.expect(reserved.ptr == buffer.reserved.ptr);
        testing.expect(reserved.len == buffer.reserved.len);
        std.mem.copy(u8, reserved[0..message_size], asByteSlice(test_message));
        try buffer.commit(message_size);
        testing.expect(buffer.size() == message_size * (i + 1));
    }
    // then put and pull out at the same time
    for (test_messages[message_count/4..]) |test_message, i| {
        var reserved = try buffer.reserve(message_size);
        testing.expect(reserved.len >= message_size);
        testing.expect(reserved.ptr == buffer.reserved.ptr);
        testing.expect(reserved.len == buffer.reserved.len);
        std.mem.copy(u8, reserved[0..message_size], asByteSlice(test_message));
        try buffer.commit(message_size);
        testing.expect(buffer.size() == message_size * (message_count/4 + 1));

        var peek = buffer.peek();
        testing.expect(peek.len >= message_size);
        testing.expect(std.mem.eql(u8, peek[0..message_size], asByteSlice(test_messages[i])));
        var block = buffer.readBlock();
        testing.expect(block.len >= message_size);
        testing.expect(std.mem.eql(u8, block[0..message_size], asByteSlice(test_messages[i])));
        try buffer.release(message_size);
        testing.expect(buffer.size() == message_size * (message_count/4));
    }
    // then pull out the last messages
    for (test_messages[message_count-message_count/4..]) |test_message, i| {
        var peek = buffer.peek();
        testing.expect(peek.len >= message_size);
        testing.expect(std.mem.eql(u8, peek[0..message_size], asByteSlice(test_message)));
        var block = buffer.readBlock();
        testing.expect(block.len >= message_size);
        testing.expect(std.mem.eql(u8, block[0..message_size], asByteSlice(test_message)));
        try buffer.release(message_size);
        testing.expect(buffer.size() == message_size * (message_count/4 - i - 1));
    }
    testing.expect(buffer.empty());
    testing.expect(buffer.size() == 0);
}

test "discard data" {
    var buffer = try BipartiteBuffer().init(debug.global_allocator, 100);
    defer buffer.deinit();

    _ = try buffer.reserve(50);
    try buffer.commit(50);
    testing.expect(buffer.size() == 50);
    try buffer.discard(30);
    testing.expect(buffer.size() == 20);
    buffer.discard(30) catch |err| testing.expect(err == BufferDiscardError.DiscardingMoreThanAvailable);
    testing.expect(!buffer.empty());
    buffer.discardAll();
    testing.expect(buffer.empty());
}

test "release data" {
    var buffer = try BipartiteBuffer().init(debug.global_allocator, 100);
    defer buffer.deinit();

    _ = try buffer.reserve(50);
    try buffer.commit(50);
    testing.expect(buffer.size() == 50);
    buffer.release(30) catch |err| testing.expect(err == BufferReleaseError.ReleasingMoreThanRead);
    _ = buffer.readBlock();
    try buffer.release(30);
    testing.expect(buffer.size() == 20);
}
