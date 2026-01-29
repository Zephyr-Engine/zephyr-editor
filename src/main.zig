const std = @import("std");
const runtime = @import("zephyr_runtime");
const EditorScene = @import("editor_scene.zig").EditorScene;

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
    const editor_scene = try EditorScene.create(allocator, app_props);
    const scene = runtime.Scene.init(editor_scene);
    application.pushScene(scene);

    application.run();
}
