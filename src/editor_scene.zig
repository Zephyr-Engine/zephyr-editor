const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const RenderCommand = runtime.RenderCommand;
const Framebuffer = runtime.Framebuffer;

// Local input bridge (translates runtime events to zgui input)
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

// File-scope var to allow panel render callbacks to access the EditorScene.
// Only one EditorScene exists, so a file-scope var is clean enough.
var editor_instance: ?*EditorScene = null;

// Menu dropdown options
const file_options = [_][]const u8{ "New", "Open", "Save", "Save As", "Exit" };
const edit_options = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste" };

const menu_height: f32 = 50;

// Layout persistence file
const layout_file = "editor_layout.txt";

// Window and cursor types from runtime
const Window = runtime.Window;
const Cursor = runtime.Cursor;
const RuntimeCursorShape = runtime.CursorShape;

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

/// Editor scene that combines game rendering with zGUI docking-based editor UI
pub const EditorScene = struct {
    allocator: std.mem.Allocator,

    // GUI
    renderer: Renderer,
    gui_ctx: *GuiContext,
    input_bridge: InputBridge,

    // Event buffer - events are buffered in onEvent and replayed after newFrame()
    // to avoid beginFrame() clearing per-frame input state before widgets read it
    event_buffer: [64]runtime.ZEvent,
    event_count: usize,

    // Docking
    docking_ctx: DockingContext,

    // Game rendering
    game_framebuffer: Framebuffer,
    game_texture_handle: TextureHandle,

    // Dimensions (logical = window size, fb = framebuffer/physical size)
    window_width: f32,
    window_height: f32,
    fb_width: u32,
    fb_height: u32,
    content_scale_x: f32,
    content_scale_y: f32,

    // Game state
    game_camera: runtime.Camera,
    game_model: ?runtime.Model,
    game_shader: ?runtime.Shader,
    game_material: ?runtime.Material,
    game_material_instance: ?runtime.MaterialInstance,

    pub fn create(allocator: std.mem.Allocator, props: runtime.ApplicationProps) !*EditorScene {
        const self = try allocator.create(EditorScene);

        const width: f32 = @floatFromInt(props.width);
        const height: f32 = @floatFromInt(props.height);

        // Create GUI renderer using zgui's embedded OpenGL renderer
        const renderer = try opengl.createEmbeddedRenderer(allocator);

        self.* = EditorScene{
            .allocator = allocator,
            .renderer = renderer,
            .gui_ctx = undefined,
            .input_bridge = undefined,
            .event_buffer = undefined,
            .event_count = 0,
            .docking_ctx = undefined,
            .game_framebuffer = undefined,
            .game_texture_handle = undefined,
            .window_width = width,
            .window_height = height,
            .fb_width = props.fb_width,
            .fb_height = props.fb_height,
            .content_scale_x = props.content_scale_x,
            .content_scale_y = props.content_scale_y,
            .game_camera = undefined,
            .game_model = null,
            .game_shader = null,
            .game_material = null,
            .game_material_instance = null,
        };

        // Create cursors using runtime Window API
        cursor_arrow = Window.createStandardCursor(.arrow);
        cursor_ibeam = Window.createStandardCursor(.ibeam);
        cursor_hand = Window.createStandardCursor(.hand);
        cursor_hresize = Window.createStandardCursor(.hresize);
        cursor_vresize = Window.createStandardCursor(.vresize);
        cursor_crosshair = Window.createStandardCursor(.crosshair);

        // Now create GUI context using pointer to self.renderer (heap-stable)
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

        // Set cursor pointers on gui_ctx so pointer-based setCursor() can
        // distinguish between cursor types in embedded mode
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

        // Create game camera
        const aspect = @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height));
        self.game_camera = runtime.Camera.new(
            .{ .x = 0, .y = 0, .z = 5 },
            std.math.pi / 4.0,
            aspect,
            0.1,
            100.0,
            true,
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
            // No saved layout - add all panels
            try self.docking_ctx.addPanel(utils.id("scene"));
            try self.docking_ctx.addPanel(utils.id("hierarchy"));
            try self.docking_ctx.addPanel(utils.id("inspector"));
            try self.docking_ctx.addPanel(utils.id("console"));
        }

        // Set file-scope instance for panel render callbacks
        editor_instance = self;

        return self;
    }

    fn getTime() f64 {
        return runtime.Window.GetTime();
    }

    pub fn onStartup(self: *EditorScene, allocator: std.mem.Allocator) !void {
        std.log.info("EditorScene starting up...", .{});

        const vs_src = @embedFile("assets/shaders/vertex.glsl");
        const fs_src = @embedFile("assets/shaders/fragment.glsl");
        const obj_src = @embedFile("assets/meshes/monkey.obj");

        self.game_shader = try runtime.Shader.init(allocator, vs_src, fs_src);
        self.game_material = try runtime.Material.init(allocator, &self.game_shader.?);
        self.game_material_instance = self.game_material.?.instaniate(.{
            .ambient = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .diffuse = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .shininess = 32.0,
        });

        self.game_model = try runtime.Model.init(allocator, obj_src, &self.game_material_instance.?, .zero);
    }

    pub fn onUpdate(self: *EditorScene, delta_time: f32) void {
        _ = delta_time;

        // 1. Render game to framebuffer
        self.game_framebuffer.bind();
        RenderCommand.Clear(.{ .x = 0.1, .y = 0.1, .z = 0.15 });

        if (self.game_model) |*model| {
            const light = runtime.Light{
                .position = .{ .x = 1.2, .y = 1.0, .z = 2.0 },
                .ambient = .{ .x = 0.2, .y = 0.2, .z = 0.2 },
                .diffuse = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
                .specular = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
            };

            if (self.game_material_instance) |*mat_inst| {
                mat_inst.setUniform("light.position", light.position);
                mat_inst.setUniform("light.ambient", light.ambient);
                mat_inst.setUniform("light.diffuse", light.diffuse);
                mat_inst.setUniform("light.specular", light.specular);
            }

            RenderCommand.Draw(model, &self.game_camera);
        }

        Framebuffer.unbind();

        // 2. Set viewport to framebuffer size, clear
        const fb_w: i32 = @intCast(self.fb_width);
        const fb_h: i32 = @intCast(self.fb_height);
        RenderCommand.SetViewport(0, 0, fb_w, fb_h);
        RenderCommand.Clear(.{ .x = 0.15, .y = 0.15, .z = 0.18 });

        // 3. newFrame() → replay buffered events → finalizeInjectedInput()
        self.gui_ctx.newFrame();

        for (self.event_buffer[0..self.event_count]) |e| {
            self.input_bridge.processEvent(e);
        }
        self.event_count = 0;

        self.gui_ctx.finalizeInjectedInput();

        // 4. Update docking bounds to fill area below menu bar
        self.docking_ctx.dock_space.bounds = Rect{
            .x = 0,
            .y = menu_height,
            .w = self.window_width,
            .h = self.window_height - menu_height,
        };

        // 5. Render menu bar
        self.renderMenuBar();

        // 6. Render docking system (tabs, splitters, drop zones, panel content)
        self.docking_ctx.render(self.gui_ctx) catch {};

        // 7. Render frame (includes dropdown overlays)
        self.gui_ctx.render(&self.renderer, fb_w, fb_h);
    }

    fn renderMenuBar(self: *EditorScene) void {
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

    pub fn onEvent(self: *EditorScene, e: runtime.ZEvent) void {
        // Buffer the event for replay after newFrame() in onUpdate.
        // This ensures per-frame input state (keys, chars) is not cleared
        // by beginFrame() before widgets can read it.
        if (self.event_count < self.event_buffer.len) {
            self.event_buffer[self.event_count] = e;
            self.event_count += 1;
        }

        // Handle events that need immediate processing (not dependent on zGUI frame timing)
        switch (e) {
            .KeyPressed => |key| {
                if (key == .Escape) {
                    runtime.Application.Shutdown();
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

    pub fn onCleanup(self: *EditorScene, allocator: std.mem.Allocator) void {
        std.log.info("EditorScene cleaning up...", .{});

        editor_instance = null;

        if (self.game_shader) |*shader| {
            shader.deinit();
        }
        if (self.game_material) |*material| {
            material.deinit();
        }

        // Save layout before cleanup
        self.docking_ctx.saveLayout(layout_file) catch |err| {
            std.log.warn("Failed to save layout: {}", .{err});
        };

        self.docking_ctx.deinit();
        self.game_framebuffer.deinit();
        self.renderer.deinit();
        self.gui_ctx.deinit();

        allocator.destroy(self.gui_ctx);
        allocator.destroy(self);
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
            const aspect = bounds.w / bounds.h;
            self.game_camera.setAspectRatio(aspect);
        }
    }

    // Display game framebuffer as texture (flipped vertically for OpenGL)
    try ctx.draw_list.setTexture(self.game_texture_handle);
    try ctx.draw_list.addRectUV(
        bounds,
        .{ 0, 1 }, // UV flipped for OpenGL FBO
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
