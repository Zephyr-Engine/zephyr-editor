const fusion = @import("fusion_runtime");
const zimp = @import("zimp");
const std = @import("std");

const ProjectState = @This();

project: *fusion.Project,
watch_handle: *zimp.WatchHandle,

pub fn init(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !ProjectState {
    const project = try allocator.create(fusion.Project);
    errdefer allocator.destroy(project);

    project.* = try fusion.openProject(allocator, io, .{ .root_path = root_path });
    errdefer project.deinit(allocator, io);

    const watch_handle = try project.watchAssets(allocator, io);
    errdefer project.stopWatchingAssets(watch_handle);
    try watch_handle.waitForInitialCook();

    return .{
        .project = project,
        .watch_handle = watch_handle,
    };
}

pub fn deinit(self: *ProjectState, allocator: std.mem.Allocator, io: std.Io) void {
    self.project.stopWatchingAssets(self.watch_handle);
    self.project.deinit(allocator, io);
    allocator.destroy(self.project);
    self.* = undefined;
}
