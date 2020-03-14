const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;
const Data2D = @import("../containers/data_2d.zig").Data2D;
const StructureOfArrays = @import("../containers/structure_of_arrays.zig").StructureOfArrays;

usingnamespace @import("float3.zig");

const Position3D = Float3;
const Velocity3D = Float3;
const Force3D = Float3;

const PointData = struct {
    const Self = @This();

    const DataContainerType = StructureOfArrays(struct{position: Position3D, velocity: Velocity3D, force: Force3D});
    data: DataContainerType,

    fn init(allocator: *Allocator) Self {
        return .{
            .data = DataContainerType.init(allocator),
        };
    }

    fn deinit(self: Self) void {
        self.data.deinit();
    }

    fn addPoints(self: *Self, points : []const Position3D) !void {
        try self.data.ensureCapacity(self.data.len + points.len);
        for (points) |point| {
            self.data.appendAssumeCapacity(.{.position=point, .velocity=Velocity3D.initZero(), .force=Force3D.initZero()});
        }
    }
};

test "PointData adding points results in the points being accessible and having velocity and force of zero" {
    const points = [_]Position3D{.{.x=0, .y=0, .z=10}, .{.x=5, .y=5, .z=5}, .{.x=-5, .y=0, .z=5}};
    var point_data = PointData.init(testing.allocator);
    defer point_data.deinit();
    try point_data.addPoints(&points);

    testing.expectEqualSlices(Position3D, &points, point_data.data.toSlice("position"));

    for (point_data.data.toSlice("velocity")) |velocity| {
        testing.expectEqual(Velocity3D.initZero(), velocity);
    }
    for (point_data.data.toSlice("force")) |force| {
        testing.expectEqual(Force3D.initZero(), force);
    }
}

const Simulation = struct {
    const Self = @This();

    heighmap : Data2D(f32),
    point_data : PointData,
    gravity : Force3D,
    time_step : f32,

    fn init(allocator: *Allocator, heighmap: Data2D(f32)) Simulation {
        return .{
            .heighmap=heighmap,
            .point_data=PointData.init(allocator),
            .gravity=.{.x=0, .y=0, .z=-9.81},
            .time_step=1e-3,
        };
    }

    fn deinit(self: Self) void {
        self.point_data.deinit();
    }

    fn iterate(self: Self) void {
        for (self.point_data.data.toSlice("position")) |*p| {
            p.z = 0;
        }
    }
};

test "points drop and stay on flat land" {
    const points = [_]Position3D{.{.x=0, .y=0, .z=10}, .{.x=5, .y=5, .z=5}, .{.x=-5, .y=-5, .z=5}};
    var simulation = Simulation.init(testing.allocator, Data2D(f32).fromSlice(&[_]f32{1,2,3,4}, 2, 2));
    defer simulation.deinit();
    try simulation.point_data.addPoints(&points);

    simulation.iterate();

    testing.expectEqual(Position3D{.x=0, .y=0, .z=0}, simulation.point_data.data.at("position", 0));
    testing.expectEqual(Position3D{.x=5, .y=5, .z=0}, simulation.point_data.data.at("position", 1));
    testing.expectEqual(Position3D{.x=-5, .y=-5, .z=0}, simulation.point_data.data.at("position", 2));
}
