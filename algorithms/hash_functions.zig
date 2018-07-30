
fn Rotate(number : u64, rotation : u6) u64
{
    return (number << rotation) | (number >> @intCast(u6, u7(@sizeOf(u64)) * u7(8) - rotation));
}

// fn Rotate(number : u32, rotation : u32) u32
// {
//     return (number << rotation) | (number >> (@sizeOf(u32) *% u32(8) -% rotation));
// }

fn SpreadNumberImpl(v : u64, n : u6) u64 {
    return if (n == 0) v else SpreadNumberImpl((v << n) +% 1, n - 1);
}

fn ReversedSpreadNumberImpl(v : u64, n : u6) u64 {
    return if (n == 0) v else ((ReversedSpreadNumberImpl(v, n -% 1) << n) +% 1);
}

const spread_bits : u64 = SpreadNumberImpl(1, 10);
const reversed_spread_bits : u64 = ReversedSpreadNumberImpl(1, 10) << 8;

// I figured it'd be nice to have irregularly spaced bits, however it is symmetric (no reason why I did that).
// If you pick spread bits it gets worse and with reversed spread bits it's terrible (avalance wise)
const special_number : u64 = reversed_spread_bits ^ spread_bits;

fn SpreadNumber(comptime IntegerType : type) u64 {
    return (spread_bits << @sizeOf(IntegerType) * 8) +% 1;
}

fn ShiftMix(val : u64) u64 {
  return val ^ (val >> 17);
}

fn RotateMix(val : u64) u64 {
  return val ^ Rotate(val, 17);
}

fn FinalizeHashTo64(seed : u64, data : u64) u64 {
    // the rotate is important here. I picked 17 because it's a prime number so it's very unlikely to create cycles which could happen if you pick 8 or 32 for example (I guess)
    return (Rotate(seed, 17) ^ data) *% special_number;
}

fn Hash64To64(seed : u64, data : u64) u64 {
    return FinalizeHashTo64(seed, data);
}

fn Hash32To64(seed : u64, data : u32) u32 {
    // this apparently need some extra mixing, used the same tactic as with 64 bit mix
    // return FinalizeHashTo64(seed, Mix(data) * SpreadNumber(@typeOf(data)));
    return FinalizeHashTo64(seed, u64(data) *% SpreadNumber(@typeOf(data)));
}


fn Hash16To64(seed : u64, data : u16) u64 {
    return FinalizeHashTo64(seed, u64(data) *% SpreadNumber(@typeOf(data)));
}


fn Hash8To64(seed : u64, data : u8) u64 {
    return FinalizeHashTo64(seed, u64(data) *% SpreadNumber(@typeOf(data)));
}

fn HashTo64(seed : u64, data : var) u64 {
    return switch (@typeOf(data))
    {
        u8 => Hash8To64(seed, data),
        u16 => Hash16To64(seed, data),
        u32 => FinalizeHashTo64(data, Hash32To64(seed, data)),
        u64 => FinalizeHashTo64(Hash64To64(seed, data), RotateMix(data) *% special_number),
        else => unreachable,
    };
}


fn Hash128to64(data_in : u128) u64 {
    // I took this from the google city hash and changed it a bit
    // Murmur-inspired hashing.
    const data = [1]u128{data_in};
    const x = @bytesToSlice(u64, @sliceToBytes(data[0..]));
    var a = (x[1] ^ x[0]) *% special_number;
    a = RotateMix(a);
    var b = (x[0] ^ a) *% special_number;
    b = RotateMix(b);
    b *%= special_number;
    return b;
}


fn RoundInteger(i : usize, comptime r : usize) usize{
    return (i / r) * r;
}

fn ShortHashLoop(byte_data : []const u8, byte_size : usize, initial_hash : u64, hash_in : u64) u64
{
    const main_loop_data_size = RoundInteger(byte_size, @sizeOf(u16) * 2);
    var hash = hash_in;
    for (@bytesToSlice([2]u16, byte_data[0..main_loop_data_size])) |loop_data| {
        hash = FinalizeHashTo64(hash, FinalizeHashTo64(HashTo64(initial_hash, loop_data[0]), HashTo64(initial_hash, loop_data[1])));
    }
    for (byte_data[main_loop_data_size..]) |loop_data| {
        hash = HashTo64(hash, loop_data);
    }
    return FinalizeHashTo64(hash, hash);
}

// quick and dirty adoption of the Murmur thing from cityhash
pub fn MurBasHash(byte_data : [] const u8, seed : u64) u64
{
    const byte_size = byte_data.len;
    var hash = seed +% byte_size *% special_number;
    const byte_data_end_size = RoundInteger(byte_size, @sizeOf(u128) * 2);
    for (@bytesToSlice([2]u128, byte_data[0..byte_data_end_size])) |loop_data|
    {
        const a = [2]u64{Hash128to64(loop_data[0]), Hash128to64(loop_data[1])};
        const b = [2]u64{hash, Hash128to64(@bytesToSlice(u128, @sliceToBytes(a[0..]))[0])};
        hash = Hash128to64(@sliceToBytes(b[0..])[0]);
    }
    var loop_data = [2]u128{0, 0};
    @memcpy(@sliceToBytes(loop_data[0..]).ptr, byte_data[byte_data_end_size..byte_data_end_size + 1].ptr, byte_size - byte_data_end_size);
    const a = [2]u64{Hash128to64(loop_data[0]), Hash128to64(loop_data[1])};
    const b = [2]u64{hash, Hash128to64(@bytesToSlice(u128, @sliceToBytes(a[0..]))[0])};
    hash = Hash128to64(@bytesToSlice(u128, @sliceToBytes(b[0..]))[0]);
    return hash;
}

pub fn BytestreamHash(byte_data: [] const u8, seed : u64) u64
{
    const byte_size = byte_data.len;
    const initial_hash = seed +% byte_size *% special_number;
    var hash = initial_hash;
    const byte_data_end_size = RoundInteger(byte_size, @sizeOf(u64) * 2);
    for (@bytesToSlice([2]u64, byte_data[0..byte_data_end_size])) |loop_data| {
        hash = FinalizeHashTo64(hash, FinalizeHashTo64(HashTo64(initial_hash, loop_data[0]), HashTo64(initial_hash, loop_data[1])));
    }
    return ShortHashLoop(byte_data[byte_data_end_size..], byte_size - byte_data_end_size, initial_hash, hash);
}


pub fn ShortHash(byte_data : [] const u8, seed : u64) u64
{
    const byte_size = byte_data.len;
    const initial_hash = seed +% byte_size *% special_number;
    return ShortHashLoop(byte_data, byte_size, initial_hash, initial_hash);
}


pub fn ByteHash(byte_data : [] const u8, seed : u64) u64
{
    const byte_size = byte_data.len;
    var hash = seed +% byte_size *% special_number;
    for (byte_data) |one_byte| {
        hash = HashTo64(hash, one_byte);
    }
    return FinalizeHashTo64(hash, hash);
}

pub fn FNVHash(byte_data : [] const u8, seed_in : u64) u64
{
    const FNV_offset_basis = 14695981039346656037;
    const FNV_prime = 1099511628211;
    var hash = u64(FNV_offset_basis);
    for (byte_data) |b|
    {
        hash *%= FNV_prime;
        hash ^= b;
    }
    const seed = [1]u64{seed_in};
    for (@sliceToBytes(seed[0..])) |b|
    {
        hash *%= FNV_prime;
        hash ^= b;
    }
    return hash;
}

const assert = @import("std").debug.assert;

test "MurBasHash" {
    const string = "Bla die bla die bla die bla blablablabla.";
    assert(MurBasHash(string, 42) != 0);
}

test "BytestreamHash" {
    const string = "Bla die bla die bla die bla blablablabla.";
    assert(BytestreamHash(string, 42) != 0);
}

test "ShortHash" {
    const string = "Bla die bla die bla die bla blablablabla.";
    assert(ShortHash(string, 42) != 0);
}

test "ByteHash" {
    const string = "Bla die bla die bla die bla blablablabla.";
    assert(ByteHash(string, 42) != 0);
}

test "FNVHash" {
    const string = "Bla die bla die bla die bla blablablabla.";
    assert(FNVHash(string, 42) != 0);
}
