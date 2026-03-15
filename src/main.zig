const std = @import("std");
const zp = @import("zephyr_runtime");
const GameScene = @import("game_scene.zig").GameScene;

pub const std_options = zp.recommended_std_options;

pub fn main() void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app = zp.Application.init(allocator, .{
        .title = "Zephyr Engine",
        .width = null,
        .height = null,
    }) catch |err| {
        std.log.err("Application init failed: {}", .{err});
        return;
    };
    defer app.deinit();

    app.pushScene(GameScene, true);
    app.run();
}
