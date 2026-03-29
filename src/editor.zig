const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const RenderCommand = runtime.RenderCommand;
const DrawList = runtime.DrawList;
const Framebuffer = runtime.Framebuffer;
const RenderPass = runtime.RenderPass;
const ShadowMap = runtime.ShadowMap;
const Window = runtime.Window;
const Cursor = runtime.Cursor;
const Input = runtime.Input;
const Camera = runtime.Camera;
const AssetManager = runtime.AssetManager;
const CameraHandle = runtime.CameraHandle;

const InputBridge = @import("gui/input_bridge.zig").InputBridge;
const PickingSystem = @import("editor/picking.zig").PickingSystem;
const OutlineRenderer = @import("editor/outline.zig").OutlineRenderer;

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

const font_data = @embedFile("assets/fonts/RobotoMono-Regular.ttf");

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
    io: std.Io,
    scene: runtime.Scene,
    allocator: std.mem.Allocator,

    // GUI
    renderer: Renderer,
    gui_ctx: *GuiContext,
    input_bridge: InputBridge,

    // Docking
    docking_ctx: DockingContext,

    // Game rendering
    game_framebuffer: Framebuffer,
    game_texture_handle: TextureHandle,
    pending_fbo_size: runtime.Vec2(i32),

    // Dimensions (logical = window size, fb = framebuffer/physical size)
    window_size: runtime.Vec2(f32),
    fb_size: runtime.Vec2(u32),
    content_scale: runtime.Vec2(f32),

    // Run loop control
    running: bool,

    time: runtime.Time,

    // Play state
    play_state: PlayState,
    editor_camera_handle: CameraHandle,
    scene_camera_handle: CameraHandle,
    scene_panel_bounds: Rect,

    // Scene state snapshot (saved on Play, restored on Stop)
    scene_snapshot: runtime.SceneSnapshot,

    // Object selection & outline
    selected_object: ?usize,
    picking_system: PickingSystem,
    outline_renderer: OutlineRenderer,

    // Draw list for batched rendering
    draw_list: DrawList,

    // Shadow mapping
    shadow_map: ShadowMap,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, app: *runtime.Application, scene: runtime.Scene) !*Editor {
        const self = try allocator.create(Editor);

        const props = app.getProps();
        const width: f32 = @floatFromInt(props.width);
        const height: f32 = @floatFromInt(props.height);

        const renderer = try opengl.createEmbeddedRenderer(allocator);

        const scene_camera_handle = AssetManager.GetActiveCameraHandle().?;
        const cam = AssetManager.GetCamera(scene_camera_handle);
        const editor_camera_handle = try AssetManager.PushCamera(allocator, cam.*);
        cam.setActive(false);

        self.* = Editor{
            .app = app,
            .io = io,
            .scene = scene,
            .allocator = allocator,
            .renderer = renderer,
            .gui_ctx = undefined,
            .input_bridge = undefined,
            .docking_ctx = undefined,
            .game_framebuffer = undefined,
            .game_texture_handle = undefined,
            .pending_fbo_size = .{ .x = 0, .y = 0 },
            .window_size = .{ .x = width, .y = height },
            .fb_size = .{ .x = props.fb_width, .y = props.fb_height },
            .content_scale = .{ .x = props.content_scale_x, .y = props.content_scale_y },
            .running = true,
            .time = runtime.Time.init(),
            .play_state = .editing,
            .editor_camera_handle = editor_camera_handle,
            .scene_camera_handle = scene_camera_handle,
            .scene_panel_bounds = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .scene_snapshot = runtime.SceneSnapshot.init(),
            .selected_object = null,
            .picking_system = undefined,
            .outline_renderer = undefined,
            .draw_list = DrawList.init(allocator),
            .shadow_map = try ShadowMap.init(allocator, 2048, 20.0),
        };

        cursor_arrow = Window.createStandardCursor(.arrow);
        cursor_ibeam = Window.createStandardCursor(.ibeam);
        cursor_hand = Window.createStandardCursor(.hand);
        cursor_hresize = Window.createStandardCursor(.hresize);
        cursor_vresize = Window.createStandardCursor(.vresize);
        cursor_crosshair = Window.createStandardCursor(.crosshair);

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
            io,
        );
        gui_ctx.setWindowSize(width, height);
        gui_ctx.updateContentScale(props.content_scale_x, props.content_scale_y);

        gui_ctx.arrow_cursor = @ptrCast(cursor_arrow);
        gui_ctx.hand_cursor = @ptrCast(cursor_hand);
        gui_ctx.hresize_cursor = @ptrCast(cursor_hresize);
        gui_ctx.vresize_cursor = @ptrCast(cursor_vresize);
        gui_ctx.ibeam_cursor = @ptrCast(cursor_ibeam);

        self.gui_ctx = gui_ctx;

        self.input_bridge = InputBridge.init(gui_ctx);

        const fb_width: i32 = @intFromFloat(width * 0.6);
        const fb_height: i32 = @intFromFloat(height * 0.7);
        self.game_framebuffer = try Framebuffer.init(fb_width, fb_height);

        self.game_texture_handle = self.renderer.wrapTexture(
            self.game_framebuffer.getColorTexture(),
            fb_width,
            fb_height,
        );

        self.picking_system = try PickingSystem.init(allocator, fb_width, fb_height);
        self.outline_renderer = try OutlineRenderer.init(allocator);

        const dock_bounds = Rect{
            .x = 0,
            .y = menu_height,
            .w = width,
            .h = height - menu_height,
        };
        self.docking_ctx = try DockingContext.init(allocator, dock_bounds);

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

        const layout_loaded = try self.docking_ctx.loadLayout(layout_file, io);
        if (!layout_loaded) {
            try self.docking_ctx.addPanel(utils.id("scene"));
            try self.docking_ctx.addPanel(utils.id("hierarchy"));
            try self.docking_ctx.addPanel(utils.id("inspector"));
            try self.docking_ctx.addPanel(utils.id("console"));
        }

        editor_instance = self;

        app.window.setEventCallback(self, editorEventCallback);

        return self;
    }

    fn handleEvent(self: *Editor, e: runtime.ZEvent) void {
        self.input_bridge.processEvent(e);
        switch (e) {
            .KeyPressed => |key| {
                if (key == .Escape) {
                    self.running = false;
                }
            },
            .WindowResize => |resize| {
                self.window_size.x = @floatFromInt(resize.width);
                self.window_size.y = @floatFromInt(resize.height);
                self.gui_ctx.setWindowSize(self.window_size.x, self.window_size.y);
            },
            .FramebufferResize => |resize| {
                self.fb_size.x = resize.width;
                self.fb_size.y = resize.height;
            },
            .ContentScaleChange => |scale| {
                self.content_scale.x = scale.x;
                self.content_scale.y = scale.y;
                self.gui_ctx.updateContentScale(scale.x, scale.y);
            },
            else => {},
        }
    }

    pub fn run(self: *Editor) void {
        self.scene.onStartup(self.allocator);

        while (self.app.window.shouldCloseWindow() and self.running) {
            const current_time = Window.GetTime();
            self.time.update(@floatCast(current_time));

            Window.HandleInput();
            self.update(self.time.delta_time);
            self.app.window.swapBuffers();
            Input.Clear();
        }

        Window.HandleInput();

        self.scene.onCleanup(self.allocator);
    }

    fn update(self: *Editor, delta_time: f32) void {
        const pw = self.pending_fbo_size.x;
        const ph = self.pending_fbo_size.y;
        if (pw > 0 and ph > 0 and
            (pw != self.game_framebuffer.width or ph != self.game_framebuffer.height))
        {
            self.game_framebuffer.resize(pw, ph) catch {};
            self.picking_system.resize(pw, ph) catch {};
            self.game_texture_handle = self.renderer.wrapTexture(
                self.game_framebuffer.getColorTexture(),
                pw,
                ph,
            );
            const fbo_w: u32 = @intCast(pw);
            const fbo_h: u32 = @intCast(ph);
            self.scene.onEvent(.{ .WindowResize = .{ .width = fbo_w, .height = fbo_h } });
            const w: f32 = @floatFromInt(fbo_w);
            const h: f32 = @floatFromInt(fbo_h);
            if (h > 0) {
                AssetManager.GetCamera(self.editor_camera_handle).setAspectRatio(w / h);
                AssetManager.GetCamera(self.scene_camera_handle).setAspectRatio(w / h);
            }
        }

        self.handleEditorCameraControls(delta_time);
        self.handleObjectSelection();

        if (self.play_state != .playing) {
            Input.setEnabled(false);
        }

        const lights = AssetManager.GetLights();
        for (lights) |light| {
            if (light.kind == .directional) {
                self.shadow_map.computeLightSpaceMatrix(light);
                self.shadow_map.renderShadowPass();
                break;
            }
        }

        self.draw_list.setShadowMap(&self.shadow_map);

        var scene_pass = RenderPass.init("scene");
        _ = scene_pass
            .setTarget(&self.game_framebuffer)
            .setClearFlags(.{ .color = true, .depth = true, .stencil = true })
            .setClearColor(0.1, 0.1, 0.15, 1.0)
            .setDepthTest(true)
            .setDrawFn(editorSceneDrawFn)
            .setUserData(self);
        scene_pass.execute();

        Input.setEnabled(true);

        const fb_w: i32 = @intCast(self.fb_size.x);
        const fb_h: i32 = @intCast(self.fb_size.y);
        RenderCommand.SetViewport(0, 0, fb_w, fb_h);
        RenderCommand.Clear(.{ .x = 0.15, .y = 0.15, .z = 0.18 });

        self.gui_ctx.newFrame();

        self.gui_ctx.finalizeInjectedInput();

        self.docking_ctx.dock_space.bounds = Rect{
            .x = 0,
            .y = menu_height,
            .w = self.window_size.x,
            .h = self.window_size.y - menu_height,
        };

        self.renderMenuBar();

        self.docking_ctx.render(self.gui_ctx) catch {};
        self.gui_ctx.render(&self.renderer, fb_w, fb_h);
    }

    fn handleEditorCameraControls(self: *Editor, delta_time: f32) void {
        if (self.play_state == .playing) return;
        if (self.docking_ctx.splitter_drag != null or self.docking_ctx.drag_state.dragging) return;

        const mouse = Input.GetMousePos();
        const b = self.scene_panel_bounds;
        const in_scene = mouse.x >= b.x and mouse.x <= b.x + b.w and
            mouse.y >= b.y and mouse.y <= b.y + b.h;
        if (!in_scene) return;

        const speed = 0.2 * delta_time;
        const editor_cam = AssetManager.GetCamera(self.editor_camera_handle);

        if (Input.IsButtonHeld(.Left)) {
            const delta = Input.GetMouseMoveDelta();
            editor_cam.pan(delta.x, delta.y, speed * 10);
        } else if (Input.IsButtonHeld(.Right)) {
            const delta = Input.GetMouseMoveDelta();
            editor_cam.fpsLook(delta.x, delta.y, speed * 10);
        }

        if (Input.IsScrollingY()) {
            const delta = Input.GetMouseScroll();
            editor_cam.zoom(delta.y, speed);
        }
    }

    fn saveSceneState(self: *Editor) void {
        self.scene_snapshot.saveWithCamera(self.allocator, self.scene_camera_handle);
    }

    fn restoreSceneState(self: *Editor) void {
        self.scene_snapshot.restore();
    }

    fn handleObjectSelection(self: *Editor) void {
        if (self.play_state == .playing) return;

        if (!Input.IsButtonPressed(.Left)) return;

        if (self.docking_ctx.splitter_drag != null or self.docking_ctx.drag_state.dragging) return;

        const mouse = Input.GetMousePos();
        const b = self.scene_panel_bounds;
        const in_scene = mouse.x >= b.x and mouse.x <= b.x + b.w and
            mouse.y >= b.y and mouse.y <= b.y + b.h;
        if (!in_scene) return;

        const local_x: i32 = @intFromFloat(mouse.x - b.x);
        const local_y: i32 = @intFromFloat(b.h - (mouse.y - b.y));

        self.selected_object = self.picking_system.pick(AssetManager.GetCamera(self.editor_camera_handle), local_x, local_y);
    }

    fn renderMenuBar(self: *Editor) void {
        const ctx = self.gui_ctx;

        const menu_rect = Rect{ .x = 0, .y = 0, .w = self.window_size.x, .h = menu_height };
        ctx.draw_list.addRect(menu_rect, ctx.theme.bg_secondary) catch {};

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
        self.docking_ctx.saveLayout(layout_file, self.io) catch |err| {
            std.log.warn("Failed to save layout: {}", .{err});
        };

        self.scene_snapshot.deinit(self.allocator);
        self.picking_system.deinit();
        self.outline_renderer.deinit();

        self.draw_list.deinit();
        self.shadow_map.deinit();
        self.docking_ctx.deinit();
        self.game_framebuffer.deinit();
        self.renderer.deinit();
        self.gui_ctx.deinit();

        self.allocator.destroy(self.gui_ctx);

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

fn editorSceneDrawFn(pass: *RenderPass) void {
    const self = pass.getUserData(Editor) orelse return;
    const active_camera = AssetManager.GetActiveCamera() orelse return;

    self.scene.onUpdate(self.time.delta_time);
    self.draw_list.collectFromScene(active_camera) catch {};
    self.draw_list.sortOpaque();
    self.draw_list.execute(active_camera);

    // Render outline for selected object
    if (self.play_state != .playing) {
        if (self.selected_object) |sel| {
            const outline_color = runtime.Vec3.new(
                @as(f32, 0x54) / 255.0,
                @as(f32, 0x6b) / 255.0,
                @as(f32, 0xe7) / 255.0,
            );
            self.outline_renderer.draw(AssetManager.GetCamera(self.editor_camera_handle), sel, outline_color, 1.03);
        }
    }
}

fn renderScenePanel(ctx: *GuiContext, bounds: Rect) !void {
    const self = editor_instance orelse return;

    const toolbar_height: f32 = 30;

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
                const editor_cam = AssetManager.GetCamera(self.editor_camera_handle);
                const scene_cam = AssetManager.GetCamera(self.scene_camera_handle);
                scene_cam.setAspectRatio(editor_cam.aspect_ratio);
                editor_cam.setActive(false);
                scene_cam.setActive(true);
                self.play_state = .playing;
                self.selected_object = null;
            }
        },
        .playing => {
            if (btn.button(ctx, "Pause", btn_opts)) {
                self.play_state = .paused;
            }
            if (btn.button(ctx, "Stop", btn_opts)) {
                self.restoreSceneState();
                AssetManager.GetCamera(self.scene_camera_handle).setActive(false);
                AssetManager.GetCamera(self.editor_camera_handle).setActive(true);
                self.play_state = .editing;
            }
        },
        .paused => {
            if (btn.button(ctx, "Resume", btn_opts)) {
                self.play_state = .playing;
            }
            if (btn.button(ctx, "Stop", btn_opts)) {
                self.restoreSceneState();
                AssetManager.GetCamera(self.scene_camera_handle).setActive(false);
                AssetManager.GetCamera(self.editor_camera_handle).setActive(true);
                self.play_state = .editing;
            }
        },
    }

    layout.endLayout(ctx);

    const scene_bounds = Rect{
        .x = bounds.x,
        .y = bounds.y + toolbar_height,
        .w = bounds.w,
        .h = bounds.h - toolbar_height,
    };

    self.scene_panel_bounds = scene_bounds;

    const new_width: i32 = @intFromFloat(scene_bounds.w);
    const new_height: i32 = @intFromFloat(scene_bounds.h);
    if (new_width > 0 and new_height > 0) {
        self.pending_fbo_size = .{ .x = new_width, .y = new_height };
    }

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
