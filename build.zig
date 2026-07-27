const std = @import("std");
const zp = @import("zephyr_runtime");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runtime_dep = b.dependency("zephyr_runtime", .{
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = runtime_dep.module("zephyr_runtime");
    const zgui_dep = b.dependency("zGUI", .{
        .target = target,
        .optimize = optimize,
    });
    const zgui_mod = zgui_dep.module("zGUI");

    const exe = b.addExecutable(.{
        .name = "zephyr_sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zephyr_runtime", .module = runtime_mod },
                .{ .name = "zGUI", .module = zgui_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
