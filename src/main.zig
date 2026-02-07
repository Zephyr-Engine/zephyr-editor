const std = @import("std");
const runtime = @import("zephyr_runtime");
const build_options = @import("build_options");
const GameScene = @import("game_scene.zig").GameScene;

pub const std_options = runtime.recommended_std_options;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application = try runtime.Application.init(allocator, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
        .samples = 4,
    });
    defer application.deinit(allocator);

    const app_props = application.getProps();
    const game_scene = try GameScene.create(allocator, app_props);

    if (comptime build_options.release) {
        application.pushScene(runtime.Scene.init(game_scene));
        application.run();
    } else {
        const Editor = @import("editor.zig").Editor;
        var editor = try Editor.init(allocator, application, runtime.Scene.init(game_scene), &game_scene.camera);
        defer editor.deinit();

        editor.run();
    }
}
