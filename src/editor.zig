const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const RenderCommand = runtime.RenderCommand;
const Framebuffer = runtime.Framebuffer;
const Window = runtime.Window;
const Cursor = runtime.Cursor;
const Input = runtime.Input;

const InputBridge = @import("gui/input_bridge.zig").InputBridge;

const GuiContext = zgui.GuiContext;
const Renderer = zgui.Renderer;
const TextureHandle = zgui.TextureHandle;
const opengl = zgui.opengl;
const PlatformCallbacks = zgui.PlatformCallbacks;
const CursorShape = zgui.CursorShape;
const Rect = zgui.shapes.Rect;
const DockingContext = zgui.docking.DockingContext;
const PanelInfo = zgui.docking.PanelInfo;
const layout = zgui.layout;
const drop = zgui.dropdown;
const utils = zgui.utils;

// Embedded font data
const font_data = @embedFile("assets/fonts/RobotoMono-Regular.ttf");

// Menu dropdown options
const file_options = [_][]const u8{ "New", "Open", "Save", "Save As", "Exit" };
const edit_options = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste" };

const menu_height: f32 = 50;

// Layout persistence file
const layout_file = "editor_layout.txt";

// File-scope var to allow panel render callbacks to access the Editor.
var editor_instance: ?*Editor = null;

// Cursor handles (created once during init)
var cursor_arrow: ?*Cursor = null;
var cursor_ibeam: ?*Cursor = null;
var cursor_hand: ?*Cursor = null;
var cursor_hresize: ?*Cursor = null;
var cursor_vresize: ?*Cursor = null;
var cursor_crosshair: ?*Cursor = null;

fn setCursorCallback(shape: CursorShape) void {
    const cursor = switch (shape) {
        .arrow => cursor_arrow,
        .ibeam => cursor_ibeam,
        .hand => cursor_hand,
        .hresize => cursor_hresize,
        .vresize => cursor_vresize,
        .crosshair => cursor_crosshair,
    };
    Window.setCurrentContextCursor(cursor);
}

fn getTime() f64 {
    return Window.GetTime();
}

/// File-scope event callback set on the Application's window.
fn editorEventCallback(app: *runtime.Application, e: runtime.ZEvent) void {
    _ = app;
    Input.Update(e);
    if (editor_instance) |editor| {
        editor.handleEvent(e);
    }
}

/// Editor application that wraps any Scene with a docking-based editor GUI.
/// The Editor is NOT a scene — it has its own run() method that replaces application.run().
pub const Editor = struct {
    app: *runtime.Application,
    scene: runtime.Scene,
    allocator: std.mem.Allocator,

    // GUI
    renderer: Renderer,
    gui_ctx: *GuiContext,
    input_bridge: InputBridge,
    event_buffer: [64]runtime.ZEvent,
    event_count: usize,

    // Docking
    docking_ctx: DockingContext,

    // Game rendering
    game_framebuffer: Framebuffer,
    game_texture_handle: TextureHandle,
    fbo_size_changed: bool,

    // Dimensions (logical = window size, fb = framebuffer/physical size)
    window_width: f32,
    window_height: f32,
    fb_width: u32,
    fb_height: u32,
    content_scale_x: f32,
    content_scale_y: f32,

    // Run loop control
    running: bool,

    // Simple time tracking
    delta_time: f32,
    last_frame: f32,

    pub fn init(allocator: std.mem.Allocator, app: *runtime.Application, scene: runtime.Scene) !*Editor {
        const self = try allocator.create(Editor);

        const props = app.getProps();
        const width: f32 = @floatFromInt(props.width);
        const height: f32 = @floatFromInt(props.height);

        // Create GUI renderer using zgui's embedded OpenGL renderer
        const renderer = try opengl.createEmbeddedRenderer(allocator);

        self.* = Editor{
            .app = app,
            .scene = scene,
            .allocator = allocator,
            .renderer = renderer,
            .gui_ctx = undefined,
            .input_bridge = undefined,
            .event_buffer = undefined,
            .event_count = 0,
            .docking_ctx = undefined,
            .game_framebuffer = undefined,
            .game_texture_handle = undefined,
            .fbo_size_changed = false,
            .window_width = width,
            .window_height = height,
            .fb_width = props.fb_width,
            .fb_height = props.fb_height,
            .content_scale_x = props.content_scale_x,
            .content_scale_y = props.content_scale_y,
            .running = true,
            .delta_time = 0.0,
            .last_frame = 0.0,
        };

        // Create cursors
        cursor_arrow = Window.createStandardCursor(.arrow);
        cursor_ibeam = Window.createStandardCursor(.ibeam);
        cursor_hand = Window.createStandardCursor(.hand);
        cursor_hresize = Window.createStandardCursor(.hresize);
        cursor_vresize = Window.createStandardCursor(.vresize);
        cursor_crosshair = Window.createStandardCursor(.crosshair);

        // Create GUI context
        const platform = PlatformCallbacks{
            .getTime = getTime,
            .setCursor = setCursorCallback,
        };

        const gui_ctx = try allocator.create(GuiContext);
        gui_ctx.* = try GuiContext.initEmbedded(
            allocator,
            &self.renderer,
            font_data,
            platform,
        );
        gui_ctx.setWindowSize(width, height);
        gui_ctx.updateContentScale(props.content_scale_x, props.content_scale_y);

        gui_ctx.arrow_cursor = @ptrCast(cursor_arrow);
        gui_ctx.hand_cursor = @ptrCast(cursor_hand);
        gui_ctx.hresize_cursor = @ptrCast(cursor_hresize);
        gui_ctx.vresize_cursor = @ptrCast(cursor_vresize);
        gui_ctx.ibeam_cursor = @ptrCast(cursor_ibeam);

        self.gui_ctx = gui_ctx;

        // Create input bridge
        self.input_bridge = InputBridge.init(gui_ctx);

        // Create framebuffer for game rendering
        const fb_width: i32 = @intFromFloat(width * 0.6);
        const fb_height: i32 = @intFromFloat(height * 0.7);
        self.game_framebuffer = try Framebuffer.init(fb_width, fb_height);

        // Wrap framebuffer texture for GUI display
        self.game_texture_handle = self.renderer.wrapTexture(
            self.game_framebuffer.getColorTexture(),
            fb_width,
            fb_height,
        );

        // Initialize docking context with bounds below menu bar
        const dock_bounds = Rect{
            .x = 0,
            .y = menu_height,
            .w = width,
            .h = height - menu_height,
        };
        self.docking_ctx = try DockingContext.init(allocator, dock_bounds);

        // Register panels
        try self.docking_ctx.registerPanel(PanelInfo{
            .id = utils.id("scene"),
            .title = "Scene",
            .render_fn = renderScenePanel,
            .closable = false,
            .min_width = 300,
            .min_height = 300,
        });

        try self.docking_ctx.registerPanel(PanelInfo{
            .id = utils.id("hierarchy"),
            .title = "Hierarchy",
            .render_fn = renderHierarchyPanel,
            .closable = true,
            .min_width = 200,
            .min_height = 200,
        });

        try self.docking_ctx.registerPanel(PanelInfo{
            .id = utils.id("inspector"),
            .title = "Inspector",
            .render_fn = renderInspectorPanel,
            .closable = true,
            .min_width = 250,
            .min_height = 200,
        });

        try self.docking_ctx.registerPanel(PanelInfo{
            .id = utils.id("console"),
            .title = "Console",
            .render_fn = renderConsolePanel,
            .closable = true,
            .min_width = 200,
            .min_height = 100,
        });

        // Try to load saved layout, otherwise add all panels
        const layout_loaded = try self.docking_ctx.loadLayout(layout_file);
        if (!layout_loaded) {
            try self.docking_ctx.addPanel(utils.id("scene"));
            try self.docking_ctx.addPanel(utils.id("hierarchy"));
            try self.docking_ctx.addPanel(utils.id("inspector"));
            try self.docking_ctx.addPanel(utils.id("console"));
        }

        // Set file-scope instance for panel render callbacks
        editor_instance = self;

        // Replace Application's event callback with our own
        app.window.setEventCallback(editorEventCallback, app);

        return self;
    }

    fn handleEvent(self: *Editor, e: runtime.ZEvent) void {
        // Buffer the event for replay after newFrame() in update.
        if (self.event_count < self.event_buffer.len) {
            self.event_buffer[self.event_count] = e;
            self.event_count += 1;
        }

        switch (e) {
            .KeyPressed => |key| {
                if (key == .Escape) {
                    self.running = false;
                }
            },
            .WindowResize => |resize| {
                self.window_width = @floatFromInt(resize.width);
                self.window_height = @floatFromInt(resize.height);
                self.gui_ctx.setWindowSize(self.window_width, self.window_height);
            },
            .FramebufferResize => |resize| {
                self.fb_width = resize.width;
                self.fb_height = resize.height;
            },
            .ContentScaleChange => |scale| {
                self.content_scale_x = scale.x;
                self.content_scale_y = scale.y;
                self.gui_ctx.updateContentScale(scale.x, scale.y);
            },
            else => {},
        }
    }

    pub fn run(self: *Editor) void {
        self.scene.onStartup(self.allocator);

        while (self.app.window.shouldCloseWindow() and self.running) {
            const current_time: f32 = @floatCast(Window.GetTime());
            self.delta_time = current_time - self.last_frame;
            self.last_frame = current_time;

            Window.HandleInput();
            self.update(self.delta_time);
            self.app.window.swapBuffers();
            Input.Clear();
        }

        Window.HandleInput();

        self.scene.onCleanup(self.allocator);
    }

    fn update(self: *Editor, delta_time: f32) void {
        // If FBO was resized last frame, forward a WindowResize event to the scene
        // so it can update camera aspect ratio
        if (self.fbo_size_changed) {
            self.fbo_size_changed = false;
            const fbo_w: u32 = @intCast(self.game_framebuffer.width);
            const fbo_h: u32 = @intCast(self.game_framebuffer.height);
            self.scene.onEvent(.{ .WindowResize = .{ .width = fbo_w, .height = fbo_h } });
        }

        // Render game to framebuffer
        self.game_framebuffer.bind();
        self.scene.onUpdate(delta_time);
        Framebuffer.unbind();

        // Set viewport to physical framebuffer size, clear screen
        const fb_w: i32 = @intCast(self.fb_width);
        const fb_h: i32 = @intCast(self.fb_height);
        RenderCommand.SetViewport(0, 0, fb_w, fb_h);
        RenderCommand.Clear(.{ .x = 0.15, .y = 0.15, .z = 0.18 });

        // newFrame() -> replay buffered events -> finalizeInjectedInput()
        self.gui_ctx.newFrame();

        for (self.event_buffer[0..self.event_count]) |e| {
            self.input_bridge.processEvent(e);
        }
        self.event_count = 0;

        self.gui_ctx.finalizeInjectedInput();

        // Update docking bounds to fill area below menu bar
        self.docking_ctx.dock_space.bounds = Rect{
            .x = 0,
            .y = menu_height,
            .w = self.window_width,
            .h = self.window_height - menu_height,
        };

        // Render menu bar
        self.renderMenuBar();

        // Render docking system (tabs, splitters, drop zones, panel content)
        self.docking_ctx.render(self.gui_ctx) catch {};

        // Render frame (includes dropdown overlays)
        self.gui_ctx.render(&self.renderer, fb_w, fb_h);
    }

    fn renderMenuBar(self: *Editor) void {
        const ctx = self.gui_ctx;

        // Menu bar background
        const menu_rect = Rect{ .x = 0, .y = 0, .w = self.window_width, .h = menu_height };
        ctx.draw_list.addRect(menu_rect, ctx.theme.bg_secondary) catch {};

        // Layout for dropdown menu buttons
        layout.beginLayout(ctx, layout.hLayout(ctx, .{
            .margin = layout.Spacing.all(10),
            .padding = layout.Spacing.all(12),
            .height = menu_height,
        }));

        if (drop.dropdown(ctx, 1, "File", &file_options, .{
            .font_size = 16,
            .padding = layout.Spacing.symmetric(6, 12),
            .border_radius = 4.0,
        }) catch null) |index| {
            std.log.info("File option selected: {s}", .{file_options[index]});
        }

        if (drop.dropdown(ctx, 2, "Edit", &edit_options, .{
            .font_size = 16,
            .padding = layout.Spacing.symmetric(6, 12),
            .border_radius = 4.0,
        }) catch null) |index| {
            std.log.info("Edit option selected: {s}", .{edit_options[index]});
        }

        layout.endLayout(ctx);

        // Title centered
        ctx.addText(self.window_width / 2 - 60, 15, "Zephyr Editor", 16, ctx.theme.text_bright) catch {};
    }

    pub fn deinit(self: *Editor) void {
        // Save layout before cleanup
        self.docking_ctx.saveLayout(layout_file) catch |err| {
            std.log.warn("Failed to save layout: {}", .{err});
        };

        self.docking_ctx.deinit();
        self.game_framebuffer.deinit();
        self.renderer.deinit();
        self.gui_ctx.deinit();

        self.allocator.destroy(self.gui_ctx);

        // Destroy cursors
        Window.destroyCursor(cursor_arrow);
        Window.destroyCursor(cursor_ibeam);
        Window.destroyCursor(cursor_hand);
        Window.destroyCursor(cursor_hresize);
        Window.destroyCursor(cursor_vresize);
        Window.destroyCursor(cursor_crosshair);
        cursor_arrow = null;
        cursor_ibeam = null;
        cursor_hand = null;
        cursor_hresize = null;
        cursor_vresize = null;
        cursor_crosshair = null;

        editor_instance = null;

        self.allocator.destroy(self);
    }
};

// Panel render callbacks (file-scope functions matching PanelRenderFn signature)

fn renderScenePanel(ctx: *GuiContext, bounds: Rect) !void {
    const self = editor_instance orelse return;

    // Resize framebuffer if needed
    const new_width: i32 = @intFromFloat(bounds.w);
    const new_height: i32 = @intFromFloat(bounds.h);
    if (new_width != self.game_framebuffer.width or new_height != self.game_framebuffer.height) {
        if (new_width > 0 and new_height > 0) {
            self.game_framebuffer.resize(new_width, new_height) catch {};
            self.game_texture_handle = self.renderer.wrapTexture(
                self.game_framebuffer.getColorTexture(),
                new_width,
                new_height,
            );
            self.fbo_size_changed = true;
        }
    }

    // Display game framebuffer as texture (flipped vertically for OpenGL)
    try ctx.draw_list.setTexture(self.game_texture_handle);
    try ctx.draw_list.addRectUV(
        bounds,
        .{ 0, 1 },
        .{ 1, 0 },
        0xFFFFFFFF,
    );
}

fn renderHierarchyPanel(ctx: *GuiContext, bounds: Rect) !void {
    var y = bounds.y + 16;
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Scene Objects:", 16, ctx.theme.text_primary);
    y += 24;

    const items = [_][]const u8{
        "  > Camera",
        "  > Monkey",
        "  > Light",
    };

    for (items) |item| {
        try ctx.addText(x, y, item, 14, ctx.theme.text_secondary);
        y += 20;
    }
}

fn renderInspectorPanel(ctx: *GuiContext, bounds: Rect) !void {
    var y = bounds.y + 16;
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Transform", 16, ctx.theme.text_primary);
    y += 24;

    try ctx.addText(x, y, "Position: 0, 0, 0", 14, ctx.theme.text_secondary);
    y += 20;

    try ctx.addText(x, y, "Rotation: 0, 0, 0", 14, ctx.theme.text_secondary);
    y += 20;

    try ctx.addText(x, y, "Scale: 1, 1, 1", 14, ctx.theme.text_secondary);
}

fn renderConsolePanel(ctx: *GuiContext, bounds: Rect) !void {
    var y = bounds.y + 16;
    const x = bounds.x + 16;

    try ctx.addText(x, y, "[INFO] Editor initialized", 14, ctx.theme.success);
    y += 18;

    try ctx.addText(x, y, "[INFO] Scene loaded", 14, ctx.theme.success);
    y += 18;

    try ctx.addText(x, y, "[INFO] Ready", 14, ctx.theme.success);
}
