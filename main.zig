pub const Algorithms = @import("algorithms/main.zig");
pub const Containers = @import("containers/main.zig");
pub const Math = @import("math/main.zig");
pub const Simulation = @import("simulation/main.zig");

comptime {
    @import("std").meta.refAllDecls(@This());
}
