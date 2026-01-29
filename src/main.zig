const std = @import("std");
const runtime = @import("zephyr_runtime");
const GameScene = @import("game_scene.zig").GameScene;
const Editor = @import("editor.zig").Editor;

pub const std_options = runtime.recommended_std_options;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application = try runtime.Application.init(allocator, .{
        .width = 1920,
        .height = 1080,
        .title = "Zephyr Editor",
        .samples = 4,
    });
    defer application.deinit(allocator);

    const app_props = application.getProps();
    const game_scene = try GameScene.create(allocator, app_props);

    var editor = try Editor.init(allocator, application, runtime.Scene.init(game_scene));
    defer editor.deinit();

    editor.run();
}
