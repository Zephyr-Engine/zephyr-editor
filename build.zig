const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runtime_dep = b.dependency("zephyr_runtime", .{
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = runtime_dep.module("zephyr_runtime");

    // zGUI dependency with build options
    const zgui_debug = b.option(bool, "zgui_debug", "Enable zGUI debug features") orelse false;
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
    });

    // Create build options for zgui
    const zgui_build_options = b.addOptions();
    zgui_build_options.addOption(bool, "debug", zgui_debug);

    // Get the zgui module and add build options
    const zgui_module = zgui_dep.module("zgui");
    zgui_module.addOptions("build_options", zgui_build_options);

    const exe = b.addExecutable(.{
        .name = "zephyr_sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zephyr_runtime", .module = runtime_mod },
                .{ .name = "zgui", .module = zgui_module },
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
