const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const RenderCommand = runtime.RenderCommand;
const Framebuffer = runtime.Framebuffer;
const Window = runtime.Window;
const Cursor = runtime.Cursor;
const Input = runtime.Input;
const Camera = runtime.Camera;
const Shader = runtime.Shader;
const AssetManager = runtime.AssetManager;

const TransformSnapshot = struct {
    position: runtime.Vec3,
    rotation: runtime.Quat,
    scale: runtime.Vec3,
};

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
const btn = zgui.button;
const utils = zgui.utils;

// Embedded font data
const font_data = @embedFile("assets/fonts/RobotoMono-Regular.ttf");

// Embedded shader sources for picking and outline
const utility_vertex_src = @embedFile("assets/shaders/utility_vertex.glsl");
const picking_fragment_src = @embedFile("assets/shaders/picking_fragment.glsl");
const outline_fragment_src = @embedFile("assets/shaders/outline_fragment.glsl");

// Menu dropdown options
const file_options = [_][]const u8{ "New", "Open", "Save", "Save As", "Exit" };
const edit_options = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste" };

const menu_height: f32 = 50;

const layout_file = "editor_layout.txt";

var editor_instance: ?*Editor = null;

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

fn editorEventCallback(self: *Editor, e: runtime.ZEvent) void {
    Input.Update(e);
    self.handleEvent(e);
}

const PlayState = enum {
    editing,
    playing,
    paused,
};

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
    pending_fbo_width: i32,
    pending_fbo_height: i32,

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

    // Play state
    play_state: PlayState,
    editor_camera: Camera,
    scene_camera: *Camera,
    initial_game_camera: Camera,
    saved_game_camera: Camera,
    scene_panel_bounds: Rect,

    // Scene state snapshot (saved on Play, restored on Stop)
    saved_transforms: std.ArrayList(TransformSnapshot),

    // Object selection & outline
    selected_object: ?usize,
    picking_framebuffer: Framebuffer,
    picking_shader: Shader,
    outline_shader: Shader,

    pub fn init(allocator: std.mem.Allocator, app: *runtime.Application, scene: runtime.Scene, scene_camera: *Camera) !*Editor {
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
            .pending_fbo_width = 0,
            .pending_fbo_height = 0,
            .window_width = width,
            .window_height = height,
            .fb_width = props.fb_width,
            .fb_height = props.fb_height,
            .content_scale_x = props.content_scale_x,
            .content_scale_y = props.content_scale_y,
            .running = true,
            .delta_time = 0.0,
            .last_frame = 0.0,
            .play_state = .editing,
            .editor_camera = scene_camera.*,
            .scene_camera = scene_camera,
            .initial_game_camera = scene_camera.*,
            .saved_game_camera = scene_camera.*,
            .scene_panel_bounds = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .saved_transforms = .empty,
            .selected_object = null,
            .picking_framebuffer = undefined,
            .picking_shader = undefined,
            .outline_shader = undefined,
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

        // Create picking framebuffer (same size as game FBO)
        self.picking_framebuffer = try Framebuffer.init(fb_width, fb_height);

        // Create picking shader and uniform map
        self.picking_shader = Shader.init(allocator, utility_vertex_src, picking_fragment_src) catch |err| {
            std.log.err("Failed to create picking shader: {}", .{err});
            return error.OutOfMemory;
        };

        // Create outline shader and uniform map
        self.outline_shader = Shader.init(allocator, utility_vertex_src, outline_fragment_src) catch |err| {
            std.log.err("Failed to create outline shader: {}", .{err});
            return error.OutOfMemory;
        };

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
        app.window.setEventCallback(self, editorEventCallback);

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
        // Apply deferred FBO resize before rendering the scene
        if (self.pending_fbo_width > 0 and self.pending_fbo_height > 0 and
            (self.pending_fbo_width != self.game_framebuffer.width or
                self.pending_fbo_height != self.game_framebuffer.height))
        {
            self.game_framebuffer.resize(self.pending_fbo_width, self.pending_fbo_height) catch {};
            self.picking_framebuffer.resize(self.pending_fbo_width, self.pending_fbo_height) catch {};
            self.game_texture_handle = self.renderer.wrapTexture(
                self.game_framebuffer.getColorTexture(),
                self.pending_fbo_width,
                self.pending_fbo_height,
            );
            const fbo_w: u32 = @intCast(self.pending_fbo_width);
            const fbo_h: u32 = @intCast(self.pending_fbo_height);
            self.scene.onEvent(.{ .WindowResize = .{ .width = fbo_w, .height = fbo_h } });
            const w: f32 = @floatFromInt(fbo_w);
            const h: f32 = @floatFromInt(fbo_h);
            if (h > 0) {
                self.editor_camera.setAspectRatio(w / h);
            }
        }

        // Handle editor camera controls (input still enabled for raw queries)
        self.handleEditorCameraControls(delta_time);

        // Handle object selection (reads picking FBO from previous frame)
        self.handleObjectSelection();

        // If editing or paused, copy editor camera to the scene camera
        if (self.play_state != .playing) {
            self.scene_camera.* = self.editor_camera;
        }

        // Disable game input when not playing
        if (self.play_state != .playing) {
            Input.setEnabled(false);
        }

        // Render game to framebuffer
        self.game_framebuffer.bind();
        self.scene.onUpdate(delta_time);

        // Render outline for selected object (into game FBO, before unbind)
        if (self.play_state != .playing) {
            if (self.selected_object) |sel| {
                // Editor accent blue: 0x546be7FF -> R=0x54, G=0x6b, B=0xe7
                const outline_color = runtime.Vec3.new(
                    @as(f32, 0x54) / 255.0,
                    @as(f32, 0x6b) / 255.0,
                    @as(f32, 0xe7) / 255.0,
                );
                RenderCommand.DrawOutline(&self.editor_camera, sel, &self.outline_shader, outline_color, 1.05);
            }
        }

        Framebuffer.unbind();

        // Re-enable input
        Input.setEnabled(true);

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

    fn handleEditorCameraControls(self: *Editor, delta_time: f32) void {
        // Only active when not playing
        if (self.play_state == .playing) return;

        // Don't move camera while dragging a docking splitter or panel tab
        if (self.docking_ctx.splitter_drag != null or self.docking_ctx.drag_state.dragging) return;

        // Check if mouse is over the scene panel
        const mouse = Input.GetMousePos();
        const b = self.scene_panel_bounds;
        const in_scene = mouse.x >= b.x and mouse.x <= b.x + b.w and
            mouse.y >= b.y and mouse.y <= b.y + b.h;
        if (!in_scene) return;

        const speed = 0.2 * delta_time;

        if (Input.IsButtonHeld(.Left)) {
            const delta = Input.GetMouseMoveDelta();
            self.editor_camera.pan(delta.x, delta.y, speed * 10);
        } else if (Input.IsButtonHeld(.Right)) {
            const delta = Input.GetMouseMoveDelta();
            self.editor_camera.fpsLook(delta.x, delta.y, speed * 10);
        }

        if (Input.IsScrollingY()) {
            const delta = Input.GetMouseScroll();
            self.editor_camera.zoom(delta.y, speed);
        }
    }

    fn saveSceneState(self: *Editor) void {
        const models = AssetManager.GetModels();
        self.saved_transforms.clearRetainingCapacity();
        self.saved_transforms.ensureTotalCapacity(self.allocator, models.len) catch return;
        for (models) |model| {
            self.saved_transforms.appendAssumeCapacity(.{
                .position = model.transform.position,
                .rotation = model.transform.rotation,
                .scale = model.transform.scale,
            });
        }
    }

    fn restoreSceneState(self: *Editor) void {
        const models = AssetManager.GetModels();
        for (models, 0..) |*model, i| {
            if (i >= self.saved_transforms.items.len) break;
            const saved = self.saved_transforms.items[i];
            model.transform.position = saved.position;
            model.transform.rotation = saved.rotation;
            model.transform.scale = saved.scale;
        }
    }

    fn handleObjectSelection(self: *Editor) void {
        // Only active when not playing
        if (self.play_state == .playing) return;

        // Only on left click (not held/drag)
        if (!Input.IsButtonPressed(.Left)) return;

        // Don't select while dragging a docking splitter or panel tab
        if (self.docking_ctx.splitter_drag != null or self.docking_ctx.drag_state.dragging) return;

        // Check if mouse is over the scene panel
        const mouse = Input.GetMousePos();
        const b = self.scene_panel_bounds;
        const in_scene = mouse.x >= b.x and mouse.x <= b.x + b.w and
            mouse.y >= b.y and mouse.y <= b.y + b.h;
        if (!in_scene) return;

        // Render picking pass on-demand
        self.picking_framebuffer.bind();
        RenderCommand.Clear(.{ .x = 0, .y = 0, .z = 0 });
        RenderCommand.DrawPicking(&self.editor_camera, &self.picking_shader);

        // Convert mouse position to FBO-local coordinates (OpenGL: Y flipped)
        const local_x: i32 = @intFromFloat(mouse.x - b.x);
        const local_y: i32 = @intFromFloat(b.h - (mouse.y - b.y));

        // Read pixel from picking FBO (still bound)
        const pixel = self.picking_framebuffer.readPixel(local_x, local_y);
        Framebuffer.unbind();
        const id: u32 = @as(u32, pixel[0]) | (@as(u32, pixel[1]) << 8) | (@as(u32, pixel[2]) << 16);

        if (id == 0) {
            // Clicked background - deselect
            self.selected_object = null;
        } else {
            self.selected_object = @intCast(id - 1);
        }
    }

    fn renderMenuBar(self: *Editor) void {
        const ctx = self.gui_ctx;

        // Menu bar background
        const menu_rect = Rect{ .x = 0, .y = 0, .w = self.window_width, .h = menu_height };
        ctx.draw_list.addRect(menu_rect, ctx.theme.bg_secondary) catch {};

        // Layout for dropdown menu buttons (left-aligned)
        layout.beginLayout(ctx, layout.Layout.init(.HORIZONTAL, 0, 0, .{
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
    }

    pub fn deinit(self: *Editor) void {
        // Save layout before cleanup
        self.docking_ctx.saveLayout(layout_file) catch |err| {
            std.log.warn("Failed to save layout: {}", .{err});
        };

        // Clean up scene state snapshot
        self.saved_transforms.deinit(self.allocator);

        // Clean up picking/outline resources
        self.picking_framebuffer.deinit();
        self.picking_shader.deinit();
        self.outline_shader.deinit();

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

    const toolbar_height: f32 = 30;

    // -- Play/Pause/Stop toolbar --
    const toolbar_rect = Rect{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = toolbar_height };
    try ctx.draw_list.addRect(toolbar_rect, ctx.theme.bg_elevated);

    const btn_opts = btn.Options{
        .font_size = 13,
        .padding = layout.Spacing.symmetric(3, 8),
        .border_radius = 4.0,
    };

    layout.beginLayout(ctx, layout.Layout.init(.HORIZONTAL, bounds.x, bounds.y, .{
        .width = bounds.w,
        .height = toolbar_height,
        .align_horizontal = .CENTER,
        .align_vertical = .CENTER,
    }));

    switch (self.play_state) {
        .editing => {
            if (btn.button(ctx, "Play", btn_opts)) {
                self.saveSceneState();
                self.scene_camera.* = self.initial_game_camera;
                self.scene_camera.setAspectRatio(self.editor_camera.aspect_ratio);
                self.play_state = .playing;
                self.selected_object = null;
            }
        },
        .playing => {
            if (btn.button(ctx, "Pause", btn_opts)) {
                self.saved_game_camera = self.scene_camera.*;
                self.play_state = .paused;
            }
            if (btn.button(ctx, "Stop", btn_opts)) {
                self.restoreSceneState();
                self.play_state = .editing;
            }
        },
        .paused => {
            if (btn.button(ctx, "Resume", btn_opts)) {
                self.scene_camera.* = self.saved_game_camera;
                self.play_state = .playing;
            }
            if (btn.button(ctx, "Stop", btn_opts)) {
                self.restoreSceneState();
                self.play_state = .editing;
            }
        },
    }

    layout.endLayout(ctx);

    // -- Scene view (below toolbar) --
    const scene_bounds = Rect{
        .x = bounds.x,
        .y = bounds.y + toolbar_height,
        .w = bounds.w,
        .h = bounds.h - toolbar_height,
    };

    // Store bounds for editor camera hit-testing
    self.scene_panel_bounds = scene_bounds;

    // Request FBO resize for next frame (deferred so current content isn't destroyed)
    const new_width: i32 = @intFromFloat(scene_bounds.w);
    const new_height: i32 = @intFromFloat(scene_bounds.h);
    if (new_width > 0 and new_height > 0) {
        self.pending_fbo_width = new_width;
        self.pending_fbo_height = new_height;
    }

    // Display game framebuffer as texture (flipped vertically for OpenGL)
    try ctx.draw_list.setTexture(self.game_texture_handle);
    try ctx.draw_list.addRectUV(
        scene_bounds,
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
    const self = editor_instance orelse return;
    const sel = self.selected_object orelse return;

    const models = AssetManager.GetModels();
    if (sel >= models.len) {
        return;
    }
    const transform = models[sel].transform;

    var y = bounds.y + 16;
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Transform", 16, ctx.theme.text_primary);
    y += 24;

    var buf: [128]u8 = undefined;

    const pos = transform.position;
    const pos_text = std.fmt.bufPrint(&buf, "Position: {d:.2}, {d:.2}, {d:.2}", .{ pos.x, pos.y, pos.z }) catch "Position: ?";
    try ctx.addText(x, y, pos_text, 14, ctx.theme.text_secondary);
    y += 20;

    const rot = transform.rotation;
    const rot_text = std.fmt.bufPrint(&buf, "Rotation: {d:.2}, {d:.2}, {d:.2}, {d:.2}", .{ rot.x, rot.y, rot.z, rot.w }) catch "Rotation: ?";
    try ctx.addText(x, y, rot_text, 14, ctx.theme.text_secondary);
    y += 20;

    const scl = transform.scale;
    const scl_text = std.fmt.bufPrint(&buf, "Scale: {d:.2}, {d:.2}, {d:.2}", .{ scl.x, scl.y, scl.z }) catch "Scale: ?";
    try ctx.addText(x, y, scl_text, 14, ctx.theme.text_secondary);
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
