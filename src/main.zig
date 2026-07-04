const std = @import("std");

const EditorUi = @import("ui/editor_ui.zig").EditorUi;
const GameScene = @import("game_scene.zig").GameScene;
const zp = @import("zephyr_runtime");
const Game = @import("game.zig");
const ui = @import("zGUI");

pub fn main(init: std.process.Init) !void {
    const manifest = try zp.createProject(init.gpa, init.io, .{
        .root_path = "/home/jparsons/repos/zephyr/zephyr-editor",
        .name = "Zephyr Game Example",
    });

    const App = zp.Application(Game);
    const app = App.init(init.gpa, init.io, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
    }, manifest) catch |err| {
        std.log.err("Application init failed: {}", .{err});
        return;
    };
    defer app.deinit() catch |err| std.log.err("Application deinit failed: {}", .{err});
    app.setDebugStatsEnabled(true);

    app.pushScene(GameScene, true);
    try app.start();

    var ui_renderer = try ui.OpenGlRenderer.init(zp.Window.getProcAddress);
    defer ui_renderer.deinit();
    std.log.info("OpenGL: {s}", .{ui.OpenGlRenderer.versionString()});

    const cwd = std.Io.Dir.cwd();
    const font_bytes = try cwd.readFileAlloc(init.io, ".zephyr/assets/fonts/Inter-Regular.ttf", init.gpa, .limited(2 * 1024 * 1024));
    defer init.gpa.free(font_bytes);
    var font_atlas = try ui.FontAtlas.init(
        init.gpa,
        font_bytes,
        1024,
        1024,
    );
    defer font_atlas.deinit();
    try ui_renderer.syncFontAtlas(&font_atlas);

    var ui_state = try ui.Ui.init(init.gpa);
    defer ui_state.deinit();
    ui_state.setFontAtlas(&font_atlas);

    var editor = try EditorUi.init(init.gpa, &ui_state);
    defer editor.deinit();

    var viewport = try zp.Framebuffer.init(1, 1);
    defer viewport.deinit();

    var ui_backend = ui.zephyr_runtime.Backend.init(init.gpa);
    defer ui_backend.deinit();

    var scene_capture: ui.zephyr_runtime.SceneInputCapture = .{};

    while (app.window.shouldCloseWindow()) {
        const runtime_events = app.beginFrame();
        const ui_frame = try ui_backend.beginFrame(app, runtime_events);

        try ui_state.beginFrame(ui_frame.toBeginFrame());

        _ = try editor.dockSpace(&ui_state, ui_frame.window_size);
        ui.zephyr_runtime.setCursor(app.window, ui_state.requestedCursor());
        editor.setViewportTexture(&ui_state, viewport.textureId());
        editor.setDebugStats(&ui_state, app.debugStats());

        ui_state.setTextRasterScale(ui_frame.text_raster_scale);
        try ui_state.endFrame();

        const viewport_rect = editor.viewportRect();
        const render_size = ui.zephyr_runtime.renderSizeForRect(viewport_rect, ui_frame.text_raster_scale);
        try viewport.resize(render_size.width, render_size.height);

        try ui.zephyr_runtime.processSceneEvents(app, runtime_events, viewport_rect, ui_state.input.mouse_pos, &scene_capture);
        try app.pumpAssets();
        try app.renderScene(&viewport);

        try ui_renderer.syncFontAtlas(&font_atlas);
        try ui_renderer.beginFrameLogical(ui_frame.framebuffer_size.width, ui_frame.framebuffer_size.height, ui_frame.window_size.x, ui_frame.window_size.y);
        try ui_renderer.render(ui_state.drawData());
        try ui_renderer.endFrame();
        app.present();
    }
}
