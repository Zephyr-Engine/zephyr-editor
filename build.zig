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

    const zimp_dep = runtime_dep.builder.dependency("zimp", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    const cook = zp.addCookStep(b, zimp_dep, .{
        .source_dir = b.path("src/assets"),
        .output_dir = b.path("src/output"),
    });
    const cook_step = b.step("cook", "Cook assets with zimp");
    cook_step.dependOn(&cook.step);

    const exe = b.addExecutable(.{
        .name = "zephyr_sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zephyr_runtime", .module = runtime_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&cook.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
