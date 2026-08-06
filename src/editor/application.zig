const zp = @import("zephyr_runtime");
const ui = @import("zGUI");
const std = @import("std");

const SceneInputCapture = @import("../ui/scene_input.zig");
const Backend = @import("../ui/zgui_runtime_backend.zig");
const ViewportTarget = @import("../viewport_target.zig");
const editor_icons = @import("../editor_icons.zig");
const EditorUi = @import("../ui/editor_ui.zig");
const Command = @import("command.zig").Command;
const Session = @import("session.zig");
const Game = @import("../game.zig");

pub fn run(allocator: std.mem.Allocator, io: std.Io, project: *const zp.Project) !void {
    const App = zp.Application(Game.definition);
    const app = try App.init(allocator, io, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
    }, project);
    defer app.deinit();
    app.setDebugStatsEnabled(true);

    try app.runtime.world.setResource(Session, .{});
    try app.start();

    var ui_renderer = try ui.OpenGlRenderer.init(allocator, zp.Window.getProcAddress);
    defer ui_renderer.deinit();

    const font_bytes = @embedFile("../resources/fonts/Inter-Regular.ttf");
    var font_atlas = try ui.FontAtlas.init(allocator, font_bytes, 1024, 1024);
    defer font_atlas.deinit();

    var icons = try editor_icons.Textures.init(&ui_renderer, allocator);
    defer icons.deinit(&ui_renderer);

    var ui_state = try ui.Ui.init(allocator);
    defer ui_state.deinit();
    ui_state.setFontAtlas(&font_atlas);

    var editor = try EditorUi.init(allocator, &ui_state, .{
        .play = icons.play,
        .pause = icons.pause,
        .stop = icons.stop,
    });
    defer editor.deinit();

    var viewport_target = try ViewportTarget.init(&app.runtime.renderer.device);
    defer viewport_target.deinit();
    var viewport_texture = try ui_renderer.registerExternalTexture(viewport_target.nativeTextureId());
    defer ui_renderer.destroyTexture(&viewport_texture);
    try editor.setViewportTexture(&ui_state, viewport_texture);

    var ui_backend = Backend.init(allocator, &ui_renderer);
    defer ui_backend.deinit();

    var scene_capture: SceneInputCapture = .{};

    while (app.window.shouldCloseWindow()) {
        const runtime_events = app.beginFrame();
        const frame = try ui_backend.beginFrame(.{
            .window_size = Backend.toUiSize(app.window.getWindowSize()),
            .framebuffer_size = Backend.toPixelSize(app.window.getFramebufferSize()),
            .dt = app.deltaTime(),
            .font_atlas = &font_atlas,
        }, runtime_events);
        try ui_state.beginFrame(frame.toBeginFrame());

        _ = try editor.dockSpace(&ui_state, frame.window_size);
        const commands = editor.commands(&ui_state);
        applyCommands(app.runtime.world.getResource(Session), commands.slice());
        Backend.setCursor(app.window, ui_state.requestedCursor());
        try editor.setDebugStats(&ui_state, app.debugStats());

        ui_state.setTextRasterScale(frame.text_raster_scale);
        try ui_state.endFrame();

        const viewport_rect = editor.viewportRect();
        _ = try viewport_target.ensureSize(viewport_rect, frame.text_raster_scale);
        scene_capture.processSceneEvents(
            app.input(),
            runtime_events,
            viewport_rect,
            ui_state.mousePosition(),
            ui_state.inputCapture().wants_mouse or editor.dock.isInteracting() or editor.controlsOwnMouse(&ui_state),
        );

        try app.update();
        if (viewport_target.renderTarget()) |target| try app.renderScene(target);

        try ui_renderer.render(ui_state.drawData());
        try ui_renderer.endFrame();
        app.present();
    }
}

fn applyCommands(session: *Session, commands: []const Command) void {
    for (commands) |command| {
        _ = session.handle(command);
    }
}

test {
    _ = @import("command.zig");
    _ = @import("session.zig");
}
