const std = @import("std");
const zp = @import("zephyr_runtime");

const default_project_name = "Zephyr Game Example";

pub const Options = struct {
    root_path: []const u8 = ".",
    create_project: bool = false,
    project_name: []const u8 = default_project_name,
};

pub fn parse(args: []const []const u8) !Options {
    var options: Options = .{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--project")) {
            i += 1;
            if (i >= args.len) return error.MissingProjectPath;
            options.root_path = args[i];
            options.create_project = true;
        } else if (std.mem.startsWith(u8, arg, "--project=")) {
            options.root_path = arg["--project=".len..];
            if (options.root_path.len == 0) return error.MissingProjectPath;
            options.create_project = true;
        } else {
            return error.UnknownArgument;
        }
    }

    return options;
}

pub fn absoluteProjectRoot(allocator: std.mem.Allocator, io: std.Io, root: []const u8) ![:0]u8 {
    if (std.fs.path.isAbsolute(root)) {
        return allocator.dupeZ(u8, root);
    }

    return std.Io.Dir.cwd().realPathFileAlloc(io, root, allocator);
}

pub fn createProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    name: []const u8,
) !void {
    const root_dir = try std.Io.Dir.openDirAbsolute(io, root_path, .{});
    errdefer root_dir.close(io);

    const project_name = try allocator.dupe(u8, name);
    defer allocator.free(project_name);

    const random_source: std.Random.IoSource = .{ .io = io };
    const manifest = zp.ProjectManifest{
        .project_id = .v4(random_source.interface()),
        .name = project_name,
    };
    errdefer manifest.deinit(allocator);

    try root_dir.createDirPath(io, manifest.generated_dir);
    try root_dir.createDirPath(io, manifest.assets_dir);
    try root_dir.createDirPath(io, manifest.scenes_dir);
    try root_dir.createDirPath(io, manifest.cooked_assets_dir);
    try manifest.save(allocator, io, root_dir);

    std.log.info("Created project at {s}", .{root_path});
}

const testing = std.testing;

test "parse defaults to opening current project" {
    const options = try parse(&.{"zephyr-editor"});

    try testing.expectEqualStrings(".", options.root_path);
    try testing.expect(!options.create_project);
}

test "parse project flag selects create mode" {
    const options = try parse(&.{ "zephyr-editor", "--project", "/tmp/project" });

    try testing.expectEqualStrings("/tmp/project", options.root_path);
    try testing.expect(options.create_project);
}

test "parse project equals flag selects create mode" {
    const options = try parse(&.{ "zephyr-editor", "--project=/tmp/project" });

    try testing.expectEqualStrings("/tmp/project", options.root_path);
    try testing.expect(options.create_project);
}
