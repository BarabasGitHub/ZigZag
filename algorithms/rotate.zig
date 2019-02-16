const std = @import("std");
const testing = std.testing;

fn swapRange(comptime T: type, data1: []T , data2: []T) void{
    testing.expect(data1.len == data2.len);
    for (data1) |*value1, i| {
      std.mem.swap(T, value1, &data2[i]);
    }
}

pub fn rotateBlock(comptime T: type, data: []T, distance: usize) void {
    testing.expect(distance <= data.len);
    if(distance == 0 or distance == data.len) return;
    // switch sizes for right rotation
    var size1 = distance;
    var size2 = data.len - distance;
    const rotation_point = size1;
    while( size1 != size2 ) {
        const begin = rotation_point - size1;
        const end = rotation_point + size2;
       if( size1 > size2 ) {
           swapRange(T, data[begin..begin + size2], data[rotation_point..end]);
           size1 -= size2;
       } else {
           swapRange(T, data[begin..rotation_point], data[end - size1..end]);
           size2 -= size1;
       }
   }
   const begin = rotation_point - size1;
   const end = rotation_point + size1;
   swapRange(T, data[begin..rotation_point], data[rotation_point..end]);
}

test "Rotate by half the distance" {
    var array = []i32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    const expected = []i32{6, 7, 8, 9, 10, 1, 2, 3, 4, 5};
    rotateBlock(i32, array[0..], array.len/2);
    testing.expect(std.mem.eql(i32, array, expected));
}

test "Rotate by 3" {
    var array = []i32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    const expected = []i32{4, 5, 6, 7, 8, 9, 10, 1, 2, 3};
    rotateBlock(i32, array[0..], 3);
    testing.expect(std.mem.eql(i32, array, expected));
}
