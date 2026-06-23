const std = @import("std");
const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

const console = @import("console.zig");
const inspector = @import("inspector.zig");
const scene = @import("scene.zig");
const viewport = @import("viewport.zig");

const resize_handle_thickness: f32 = 4;

const min_side_width: f32 = 190;
const min_center_width: f32 = 240;
const min_bottom_height: f32 = 96;
const min_main_height: f32 = 240;

const EditorNodes = struct {
    viewport_image: ui.NodeId,
    viewport_stats: viewport.Nodes,
    dock_host: ui.NodeId,
    left_panel: ui.NodeId,
    center_panel: ui.NodeId,
    right_panel: ui.NodeId,
    console_panel: ui.NodeId,
};

const EditorDockRefs = struct {
    viewport_window: ui.DockWindowId,
};

pub const EditorUi = struct {
    dock: ui.DockSpace,
    refs: EditorDockRefs,
    nodes: EditorNodes,
    stats_text: [128]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, state: *ui.Ui) !EditorUi {
        state.setTheme(ui.theme.zephyr_dark);

        var dock = try ui.DockSpace.init(allocator);
        errdefer dock.deinit();

        const nodes = try createEditorTree(state);
        const refs = try createDockTree(&dock, nodes);

        return .{
            .dock = dock,
            .refs = refs,
            .nodes = nodes,
        };
    }

    pub fn deinit(self: *EditorUi) void {
        self.dock.deinit();
    }

    pub fn dockSpace(self: *EditorUi, state: *ui.Ui, window_size: ui.Vec2) !ui.DockSpaceResult {
        const available_width = @max(1, window_size.x);
        const available_height = @max(1, window_size.y);
        return ui.widgets.dockSpace(state, self.nodes.dock_host, &self.dock, .{
            .rect = .{
                .x = 0,
                .y = 0,
                .w = available_width,
                .h = available_height,
            },
            .handle_thickness = resize_handle_thickness,
            .tab_height = 30,
        });
    }

    pub fn setViewportTexture(self: *const EditorUi, state: *ui.Ui, texture_id: u32) void {
        viewport.setTexture(state, self.nodes.viewport_image, texture_id);
    }

    pub fn setDebugStats(self: *EditorUi, state: *ui.Ui, stats: ?zp.DebugStats) void {
        viewport.setStats(state, self.nodes.viewport_stats, &self.stats_text, stats);
    }

    pub fn viewportRect(self: *const EditorUi) ui.Rect {
        return self.dock.windowContentRect(self.refs.viewport_window) orelse .{};
    }
};

fn createDockTree(dock: *ui.DockSpace, nodes: EditorNodes) !EditorDockRefs {
    const scene_window = try dock.createWindow("Scene", nodes.left_panel, .{ .x = min_side_width, .y = min_main_height }, .{});
    const viewport_window = try dock.createWindow("Viewport", nodes.center_panel, .{ .x = min_center_width, .y = min_main_height }, .{});
    const inspector_window = try dock.createWindow("Inspector", nodes.right_panel, .{ .x = min_side_width, .y = min_main_height }, .{});
    const console_window = try dock.createWindow("Console", nodes.console_panel, .{ .x = min_center_width, .y = min_bottom_height }, .{});

    try dock.dock.moveWindowToLeaf(viewport_window, dock.dock.root);

    const right = try dock.splitNode(dock.dock.root, .right, 0.72);
    try dock.setSplitMinimums(right.split, min_center_width + min_side_width, min_side_width);
    try dock.dock.moveWindowToLeaf(inspector_window, right.new_leaf);

    const bottom = try dock.splitNode(right.old_node, .bottom, 0.74);
    try dock.setSplitMinimums(bottom.split, min_main_height, min_bottom_height);
    try dock.dock.moveWindowToLeaf(console_window, bottom.new_leaf);

    const left = try dock.splitNode(bottom.old_node, .left, 0.26);
    try dock.setSplitMinimums(left.split, min_side_width, min_center_width);
    try dock.dock.moveWindowToLeaf(scene_window, left.new_leaf);

    return .{
        .viewport_window = viewport_window,
    };
}

fn createEditorTree(state: *ui.Ui) !EditorNodes {
    const root = state.root;
    state.tree.get(root).?.style = state.theme.style(.{
        .width = .fill,
        .height = .fill,
        .direction = .column,
        .background = .app,
    });

    const dock_host = try ui.widgets.surface(state, root, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .app,
    });

    const scene_panel = try scene.build(state, dock_host);
    const viewport_nodes = try viewport.build(state, dock_host);
    const inspector_panel = try inspector.build(state, dock_host);
    const console_panel = try console.build(state, dock_host);

    return .{
        .viewport_image = viewport_nodes.image,
        .viewport_stats = viewport_nodes,
        .dock_host = dock_host,
        .left_panel = scene_panel,
        .center_panel = viewport_nodes.root,
        .right_panel = inspector_panel,
        .console_panel = console_panel,
    };
}
