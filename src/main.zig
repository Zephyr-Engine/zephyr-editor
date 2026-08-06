const builtin = @import("builtin");
const std = @import("std");

const ui_runtime = @import("ui/zgui_runtime_backend.zig");
const ViewportTarget = @import("viewport_target.zig");
const EditorUi = @import("ui/editor_ui.zig").EditorUi;
const scene_input = @import("ui/scene_input.zig");
const editor_icons = @import("editor_icons.zig");
const viewport_mod = @import("ui/viewport.zig");
const log = @import("utilities/log.zig");
const zp = @import("zephyr_runtime");
const cli = @import("cli/root.zig");
const Game = @import("game.zig");
const ui = @import("zGUI");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = cli.parse(args) catch |err| {
        log.err("Invalid editor arguments: {}", .{err});
        return;
    };

    const project_root = try cli.absoluteProjectRoot(init.gpa, init.io, options.root_path);
    defer init.gpa.free(project_root);

    if (options.create_project) {
        try cli.createProject(init.gpa, init.io, project_root, options.project_name);
        return;
    }

    var project = try zp.openProject(init.gpa, init.io, .{ .root_path = project_root });
    defer project.deinit(init.gpa, init.io);

    const watch_handle = try project.watchAssets(init.gpa, init.io);
    defer project.stopWatchingAssets(watch_handle);

    watch_handle.waitForInitialCook() catch |err| {
        log.err("Failed to cook initial assets: {}", .{err});
        return;
    };

    const App = zp.Application(Game.definition);
    const app = App.init(init.gpa, init.io, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
    }, &project) catch |err| {
        log.err("Application init failed: {}", .{err});
        return;
    };
    defer app.deinit();
    app.setDebugStatsEnabled(true);

    try app.start();

    var ui_renderer = try ui.OpenGlRenderer.init(init.gpa, zp.Window.getProcAddress);
    defer ui_renderer.deinit();
    log.info("OpenGL: {s}", .{ui.OpenGlRenderer.versionString()});

    const font_bytes = @embedFile("resources/fonts/Inter-Regular.ttf");
    var font_atlas = try ui.FontAtlas.init(
        init.gpa,
        font_bytes,
        1024,
        1024,
    );
    defer font_atlas.deinit();
    try ui_renderer.syncFontAtlas(&font_atlas);

    var icons = try editor_icons.Textures.init(&ui_renderer, init.gpa);
    defer icons.deinit(&ui_renderer);

    var ui_state = try ui.Ui.init(init.gpa);
    defer ui_state.deinit();
    ui_state.setFontAtlas(&font_atlas);

    var control_textures = viewport_mod.ControlTextures{
        .play = icons.play,
        .pause = icons.pause,
        .stop = icons.stop,
        .state = .Stop,
    };

    var editor = try EditorUi.init(init.gpa, &ui_state, &control_textures);
    defer editor.deinit();

    var viewport = try ViewportTarget.init(&app.runtime.renderer.device);
    defer viewport.deinit();
    var viewport_texture = try ui_renderer.registerExternalTexture(viewport.nativeTextureId());
    defer ui_renderer.destroyTexture(&viewport_texture);

    var ui_backend = ui_runtime.Backend.init(init.gpa);
    defer ui_backend.deinit();

    var scene_capture: scene_input.SceneInputCapture = .{};

    while (app.window.shouldCloseWindow()) {
        const runtime_events = app.beginFrame();
        const ui_frame = try ui_backend.beginFrame(.{
            .window_size = ui_runtime.toUiSize(app.window.getWindowSize()),
            .framebuffer_size = ui_runtime.toPixelSize(app.window.getFramebufferSize()),
            .dt = app.deltaTime(),
        }, runtime_events);

        try ui_state.beginFrame(ui_frame.toBeginFrame());

        _ = try editor.dockSpace(&ui_state, ui_frame.window_size);
        editor.processControls(&ui_state);
        ui_runtime.setCursor(app.window, ui_state.requestedCursor());
        try editor.setViewportTexture(&ui_state, viewport_texture);
        try editor.setDebugStats(&ui_state, app.debugStats(), app.deltaTime());

        ui_state.setTextRasterScale(ui_frame.text_raster_scale);
        try ui_state.endFrame();

        const viewport_rect = editor.viewportRect();
        _ = try viewport.ensureSize(viewport_rect, ui_frame.text_raster_scale);

        const ui_owns_mouse = ui_state.inputCapture().wants_mouse or editor.dock.isInteracting() or editor.controlsOwnMouse(&ui_state);
        scene_input.processSceneEvents(
            app.input(),
            runtime_events,
            viewport_rect,
            ui_state.mousePosition(),
            &scene_capture,
            ui_owns_mouse,
        );
        try app.update();

        if (viewport.renderTarget()) |target| {
            try app.renderScene(target);
        }

        try ui_renderer.syncFontAtlas(&font_atlas);
        try ui_renderer.beginFrameLogical(
            ui_frame.framebuffer_size.width,
            ui_frame.framebuffer_size.height,
            ui_frame.window_size.x,
            ui_frame.window_size.y,
        );
        try ui_renderer.render(ui_state.drawData());
        try ui_renderer.endFrame();
        app.present();
    }
}
