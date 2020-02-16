pub const Algorithms = @import("algorithms/main.zig");
pub const Containers = @import("containers/main.zig");
pub const Math = @import("math/main.zig");

comptime {
    @import("std").meta.refAllDecls(@This());
}
