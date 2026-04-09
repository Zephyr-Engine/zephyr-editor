const std = @import("std");
const zp = @import("zephyr_runtime");
const GameScene = @import("game_scene.zig").GameScene;

pub const std_options = zp.recommended_std_options;

pub fn main(init: std.process.Init) void {
    const app = zp.Application.init(init.gpa, init.io, .{
        .title = "Zephyr Engine",
        .width = null,
        .height = null,
    }) catch |err| {
        std.log.err("Application init failed: {}", .{err});
        return;
    };
    defer app.deinit() catch |err| std.log.err("Application deinit failed: {}", .{err});

    app.pushScene(GameScene, true);
    app.run();
}
