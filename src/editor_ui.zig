const std = @import("std");
const ui = @import("zGUI_retained");

const toolbar_height: f32 = 52;
const resize_handle_thickness: f32 = 8;

const min_side_width: f32 = 190;
const min_center_width: f32 = 240;
const min_bottom_height: f32 = 96;
const min_main_height: f32 = 240;

const SidebarItem = struct {
    label: []const u8,
    detail: []const u8 = "",
    active: bool = false,
};

const InspectorField = struct {
    label: []const u8,
    value: []const u8,
};

const LogItem = struct {
    level: []const u8,
    message: []const u8,
    detail: []const u8,
    accent: ui.ColorRole,
};

const EditorNodes = struct {
    stats_label: ui.NodeId,
    viewport_image: ui.NodeId,
    main_area: ui.NodeId,
    left_panel: ui.NodeId,
    left_handle: ui.NodeId,
    center_panel: ui.NodeId,
    right_handle: ui.NodeId,
    right_panel: ui.NodeId,
    bottom_handle: ui.NodeId,
    console_panel: ui.NodeId,
};

const EditorDockRefs = struct {
    bottom_split: ui.DockNodeId,
    left_split: ui.DockNodeId,
    right_split: ui.DockNodeId,
    main_node: ui.DockNodeId,
    left_leaf: ui.DockNodeId,
    center_leaf: ui.DockNodeId,
    right_leaf: ui.DockNodeId,
    console_leaf: ui.DockNodeId,
};

pub const ResizeInputResult = struct {
    changed: bool,
    cursor: ui.CursorKind,
};

pub const EditorUi = struct {
    dock: ui.DockManager,
    refs: EditorDockRefs,
    nodes: EditorNodes,
    stats_text: [256]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, state: *ui.Ui) !EditorUi {
        state.setTheme(ui.theme.zephyr_dark);

        var dock = try ui.DockManager.init(allocator);
        errdefer dock.deinit();

        const refs = try createDockTree(&dock);
        const nodes = try createEditorTree(state);

        return .{
            .dock = dock,
            .refs = refs,
            .nodes = nodes,
        };
    }

    pub fn deinit(self: *EditorUi) void {
        self.dock.deinit();
    }

    pub fn layoutDock(self: *EditorUi, window_size: ui.Vec2) void {
        const available_width = @max(1, window_size.x - resize_handle_thickness * 2);
        const available_height = @max(1, window_size.y - toolbar_height - resize_handle_thickness);
        self.dock.layout(.{
            .x = 0,
            .y = toolbar_height,
            .w = available_width,
            .h = available_height,
        });
    }

    pub fn updateResizeInput(self: *EditorUi, state: *ui.Ui) ResizeInputResult {
        const hovered_split = self.hoveredSplit(state);
        if (ui.input.mousePressed(state.input, .left)) {
            if (hovered_split) |split| {
                self.dock.beginResize(split, state.input.mouse_pos) catch {};
            }
        }

        const changed = if (ui.input.mouseDown(state.input, .left))
            self.dock.updateResize(state.input.mouse_pos)
        else
            false;

        if (ui.input.mouseReleased(state.input, .left)) {
            self.dock.endResize();
        }

        const cursor = if (self.dock.activeResizeSplit()) |split|
            self.cursorForSplit(split)
        else if (hovered_split) |split|
            self.cursorForSplit(split)
        else
            ui.CursorKind.arrow;

        self.updateHandleStyles(state, hovered_split);
        return .{
            .changed = changed,
            .cursor = cursor,
        };
    }

    pub fn applyPanelStyles(self: *EditorUi, state: *ui.Ui) void {
        const main_rect = self.dock.nodeRect(self.refs.main_node) orelse ui.Rect{};
        const console_rect = self.dock.nodeRect(self.refs.console_leaf) orelse ui.Rect{};
        const left_rect = self.dock.nodeRect(self.refs.left_leaf) orelse ui.Rect{};
        const center_rect = self.dock.nodeRect(self.refs.center_leaf) orelse ui.Rect{};
        const right_rect = self.dock.nodeRect(self.refs.right_leaf) orelse ui.Rect{};

        setNodeHeight(state, self.nodes.main_area, main_rect.h);
        setNodeHeight(state, self.nodes.console_panel, console_rect.h);
        setNodeWidth(state, self.nodes.left_panel, left_rect.w);
        setNodeWidth(state, self.nodes.center_panel, center_rect.w);
        setNodeWidth(state, self.nodes.right_panel, right_rect.w);
    }

    pub fn setViewportTexture(self: *const EditorUi, state: *ui.Ui, texture_id: u32) void {
        ui.widgets.setImage(state, self.nodes.viewport_image, .{
            .texture_id = texture_id,
            .uv0 = .{ .x = 0, .y = 1 },
            .uv1 = .{ .x = 1, .y = 0 },
            .tint = ui.Color.rgba(255, 255, 255, 255),
        });
    }

    pub fn viewportRect(self: *const EditorUi, state: *const ui.Ui) ui.Rect {
        return if (state.tree.getConst(self.nodes.viewport_image)) |node| node.bounds else .{};
    }

    pub fn updateStats(self: *EditorUi, state: *ui.Ui, viewport_size: anytype) !void {
        state.tree.get(self.nodes.stats_label).?.text = try std.fmt.bufPrint(
            &self.stats_text,
            "Viewport {d}x{d}    Nodes {d}    Commands {d}    Vertices {d}    Batches {d}",
            .{
                viewport_size.width,
                viewport_size.height,
                state.stats.node_count,
                state.stats.paint_command_count,
                state.stats.vertex_count,
                state.stats.batch_count,
            },
        );
    }

    fn hoveredSplit(self: *const EditorUi, state: *const ui.Ui) ?ui.DockNodeId {
        if (ui.input.nodeHovered(state.input, self.nodes.left_handle)) return self.refs.left_split;
        if (ui.input.nodeHovered(state.input, self.nodes.right_handle)) return self.refs.right_split;
        if (ui.input.nodeHovered(state.input, self.nodes.bottom_handle)) return self.refs.bottom_split;
        return null;
    }

    fn cursorForSplit(self: *const EditorUi, split: ui.DockNodeId) ui.CursorKind {
        return switch (self.dock.splitAxis(split) orelse .x) {
            .x => .resize_x,
            .y => .resize_y,
        };
    }

    fn updateHandleStyles(self: *const EditorUi, state: *ui.Ui, hovered_split: ?ui.DockNodeId) void {
        const active_split = self.dock.activeResizeSplit();
        self.setHandleStyle(state, self.nodes.left_handle, isSplitHighlighted(self.refs.left_split, hovered_split, active_split));
        self.setHandleStyle(state, self.nodes.right_handle, isSplitHighlighted(self.refs.right_split, hovered_split, active_split));
        self.setHandleStyle(state, self.nodes.bottom_handle, isSplitHighlighted(self.refs.bottom_split, hovered_split, active_split));
    }

    fn setHandleStyle(self: *const EditorUi, state: *ui.Ui, handle: ui.NodeId, highlighted: bool) void {
        _ = self;
        if (state.tree.get(handle)) |node| {
            node.style.background = if (highlighted)
                state.theme.color(.accent)
            else
                state.theme.color(.transparent);
            node.dirty.paint = true;
        }
    }
};

fn createDockTree(dock: *ui.DockManager) !EditorDockRefs {
    const bottom = try dock.splitNode(dock.root, .bottom, 0.82);
    try dock.setSplitMinimums(bottom.split, min_main_height, min_bottom_height);

    const left = try dock.splitNode(bottom.old_node, .left, 0.18);
    try dock.setSplitMinimums(left.split, min_side_width, min_center_width + min_side_width);

    const right = try dock.splitNode(left.old_node, .right, 0.72);
    try dock.setSplitMinimums(right.split, min_center_width, min_side_width);

    return .{
        .bottom_split = bottom.split,
        .left_split = left.split,
        .right_split = right.split,
        .main_node = bottom.old_node,
        .left_leaf = left.new_leaf,
        .center_leaf = right.old_node,
        .right_leaf = right.new_leaf,
        .console_leaf = bottom.new_leaf,
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

    const toolbar = try ui.widgets.row(state, root, .{
        .width = .fill,
        .height = .{ .px = toolbar_height },
        .padding = ui.Edges{ .left = 16, .right = 16, .top = 8, .bottom = 8 },
        .gap = 12,
        .background = .shell,
        .border = .stroke_soft,
        .border_edges = ui.Edges{ .bottom = 1 },
    });

    const brand = try ui.widgets.row(state, toolbar, .{
        .width = .{ .px = 178 },
        .height = .fill,
        .gap = 8,
    });
    _ = try ui.widgets.text(state, brand, "Zephyr", .{
        .width = .{ .px = 70 },
        .height = .fill,
        .padding = ui.Edges{ .top = 6 },
        .size = state.theme.font.brand,
    });
    _ = try ui.widgets.pill(state, brand, "DEV", .{ .width = 40 });

    const breadcrumb = try ui.widgets.row(state, toolbar, .{
        .width = .fill,
        .height = .fill,
        .gap = 8,
    });
    _ = try ui.widgets.text(state, breadcrumb, "My Projects", .{
        .height = .fill,
        .padding = ui.Edges{ .top = 8 },
        .color = .text_muted,
        .size = state.theme.font.small,
    });
    _ = try ui.widgets.text(state, breadcrumb, "/", .{
        .height = .fill,
        .padding = ui.Edges{ .top = 8 },
        .color = .stroke,
        .size = state.theme.font.small,
    });
    _ = try ui.widgets.text(state, breadcrumb, "Sandbox Scene", .{
        .height = .fill,
        .padding = ui.Edges{ .top = 8 },
        .size = state.theme.font.body,
    });

    const toolbar_actions = try ui.widgets.row(state, toolbar, .{
        .width = .hug,
        .height = .fill,
        .gap = 8,
    });
    _ = try ui.widgets.text(state, toolbar_actions, "Saved 2m ago", .{
        .width = .{ .px = 92 },
        .height = .fill,
        .padding = ui.Edges{ .top = 8 },
        .color = .text_muted,
        .size = state.theme.font.small,
    });
    _ = try ui.widgets.toolbarButton(state, toolbar_actions, "Run", 58, .neutral);
    _ = try ui.widgets.toolbarButton(state, toolbar_actions, "Publish", 76, .primary);
    _ = try ui.widgets.pill(state, toolbar_actions, "JP", .{
        .width = 34,
        .background = .violet,
        .border = .violet,
    });

    const main_area = try ui.widgets.row(state, root, .{
        .width = .fill,
        .height = .fill,
        .gap = 0,
        .background = .app,
    });

    const left_panel = try buildLeftPanel(state, main_area, 252);

    const left_handle = try ui.widgets.resizeHandle(state, main_area, state.theme.style(.{
        .width = .{ .px = resize_handle_thickness },
        .height = .fill,
    }));

    const center = try ui.widgets.column(state, main_area, .{
        .width = .fill,
        .height = .fill,
        .gap = 10,
        .padding = ui.Edges{ .left = 10, .right = 10, .top = 10, .bottom = 10 },
        .background = .app,
    });

    const scene_tabs = try ui.widgets.row(state, center, .{
        .width = .fill,
        .height = .{ .px = 42 },
        .gap = 8,
        .padding = ui.Edges{ .left = 6, .right = 6, .top = 5, .bottom = 5 },
        .background = .panel,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .card,
    });
    _ = try ui.widgets.pill(state, scene_tabs, "Scene", .{ .width = 64 });
    _ = try ui.widgets.pill(state, scene_tabs, "Game", .{ .width = 58, .foreground = .text_muted, .background = .transparent, .border = .stroke_soft });
    _ = try ui.widgets.pill(state, scene_tabs, "Assets", .{ .width = 66, .foreground = .text_muted, .background = .transparent, .border = .stroke_soft });
    _ = try ui.widgets.spacer(state, scene_tabs);
    _ = try ui.widgets.toolbarButton(state, scene_tabs, "Select", 70, .neutral);
    _ = try ui.widgets.toolbarButton(state, scene_tabs, "Move", 60, .neutral);
    _ = try ui.widgets.toolbarButton(state, scene_tabs, "Play", 58, .primary);

    const viewport_image = try ui.widgets.image(state, center, .{
        .texture_id = 0,
        .style = state.theme.style(.{
            .width = .fill,
            .height = .fill,
            .background = .viewport,
            .border = .stroke,
            .border_width = 1,
            .radius = .viewport,
        }),
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .interactive = true,
    });

    const right_handle = try ui.widgets.resizeHandle(state, main_area, state.theme.style(.{
        .width = .{ .px = resize_handle_thickness },
        .height = .fill,
    }));

    const right_panel = try buildInspectorPanel(state, main_area, 306);

    const bottom_handle = try ui.widgets.resizeHandle(state, root, state.theme.style(.{
        .width = .fill,
        .height = .{ .px = resize_handle_thickness },
    }));

    const console = try ui.widgets.column(state, root, .{
        .width = .fill,
        .height = .{ .px = 136 },
        .gap = 8,
        .padding = ui.Edges{ .left = 12, .right = 12, .top = 10, .bottom = 10 },
        .background = .shell,
        .border = .stroke_soft,
        .border_edges = ui.Edges{ .top = 1 },
    });

    const console_header = try ui.widgets.row(state, console, .{
        .width = .fill,
        .height = .{ .px = 28 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, console_header, "Console", .{
        .width = .{ .px = 72 },
        .height = .fill,
        .padding = ui.Edges{ .top = 6 },
        .size = 14,
    });
    _ = try ui.widgets.pill(state, console_header, "Output", .{ .width = 62 });
    _ = try ui.widgets.pill(state, console_header, "Problems 0", .{ .width = 90, .foreground = .text_muted, .background = .transparent, .border = .stroke_soft });
    _ = try ui.widgets.spacer(state, console_header);
    const stats_label = try ui.widgets.text(state, console_header, "Viewport 0x0", .{
        .width = .{ .px = 520 },
        .height = .fill,
        .padding = ui.Edges{ .top = 7 },
        .color = .text_muted,
        .size = state.theme.font.small,
    });

    try buildConsoleRows(state, console);

    return .{
        .stats_label = stats_label,
        .viewport_image = viewport_image,
        .main_area = main_area,
        .left_panel = left_panel,
        .left_handle = left_handle,
        .center_panel = center,
        .right_handle = right_handle,
        .right_panel = right_panel,
        .bottom_handle = bottom_handle,
        .console_panel = console,
    };
}

fn buildLeftPanel(state: *ui.Ui, parent: ui.NodeId, width: f32) !ui.NodeId {
    const panel = try ui.widgets.column(state, parent, .{
        .width = .{ .px = width },
        .height = .fill,
        .gap = 10,
        .padding = ui.Edges{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .background = .panel,
        .border = .stroke_soft,
        .border_edges = ui.Edges{ .right = 1 },
        .radius = .card,
    });

    const header = try ui.widgets.row(state, panel, .{
        .width = .fill,
        .height = .{ .px = 30 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, header, "Scene", .{
        .width = .fill,
        .height = .fill,
        .padding = ui.Edges{ .top = 6 },
        .size = state.theme.font.title,
    });
    _ = try ui.widgets.pill(state, header, "LIVE", .{
        .width = 46,
        .foreground = .success,
        .background = .success_soft,
        .border = .success_soft,
    });

    _ = try searchBox(state, panel, "Search entities or assets");
    _ = try ui.widgets.sectionLabel(state, panel, "OUTLINER");

    const scene_items = [_]SidebarItem{
        .{ .label = "World Root", .detail = "4" },
        .{ .label = "Camera Rig", .detail = "1" },
        .{ .label = "Monkey Mesh", .detail = "Selected", .active = true },
        .{ .label = "Key Light", .detail = "On" },
    };
    for (scene_items) |item| {
        try sidebarRow(state, panel, item);
    }

    _ = try ui.widgets.divider(state, panel);
    _ = try ui.widgets.sectionLabel(state, panel, "ASSETS");
    const asset_items = [_]SidebarItem{
        .{ .label = "Meshes", .detail = "12" },
        .{ .label = "Materials", .detail = "8" },
        .{ .label = "Textures", .detail = "24" },
    };
    for (asset_items) |item| {
        try sidebarRow(state, panel, item);
    }

    _ = try ui.widgets.spacer(state, panel);
    _ = try statusCard(state, panel, "Renderer ready", "OpenGL viewport active");
    return panel;
}

fn buildInspectorPanel(state: *ui.Ui, parent: ui.NodeId, width: f32) !ui.NodeId {
    const panel = try ui.widgets.column(state, parent, .{
        .width = .{ .px = width },
        .height = .fill,
        .gap = 10,
        .padding = ui.Edges{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .background = .panel,
        .border = .stroke_soft,
        .border_edges = ui.Edges{ .left = 1 },
        .radius = .card,
    });

    const header = try ui.widgets.row(state, panel, .{
        .width = .fill,
        .height = .{ .px = 30 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, header, "Inspector", .{
        .width = .fill,
        .height = .fill,
        .padding = ui.Edges{ .top = 6 },
        .size = state.theme.font.title,
    });
    _ = try ui.widgets.pill(state, header, "Mesh", .{
        .width = 48,
        .foreground = .accent,
        .background = .accent_soft,
        .border = .accent_soft,
    });

    _ = try objectCard(state, panel);

    const transform_fields = [_]InspectorField{
        .{ .label = "Position", .value = "0.00, 0.00, 0.00" },
        .{ .label = "Rotation", .value = "0.00, 0.00, 0.00" },
        .{ .label = "Scale", .value = "1.00, 1.00, 1.00" },
    };
    try inspectorSection(state, panel, "TRANSFORM", &transform_fields);

    const render_fields = [_]InspectorField{
        .{ .label = "Mesh", .value = "monkey.zmesh" },
        .{ .label = "Material", .value = "monkey.zamat" },
        .{ .label = "Visible", .value = "Enabled" },
    };
    try inspectorSection(state, panel, "RENDERER", &render_fields);

    const light_fields = [_]InspectorField{
        .{ .label = "Main Light", .value = "Key Light" },
        .{ .label = "Exposure", .value = "1.00" },
    };
    try inspectorSection(state, panel, "SCENE CONTEXT", &light_fields);

    _ = try ui.widgets.spacer(state, panel);
    _ = try ui.widgets.primaryButton(state, panel, "Apply Changes");
    return panel;
}

fn buildConsoleRows(state: *ui.Ui, parent: ui.NodeId) !void {
    const rows = try ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 8,
    });
    const logs = [_]LogItem{
        .{ .level = "INFO", .message = "Loaded monkey.zmesh", .detail = "asset cache", .accent = .success },
        .{ .level = "GPU", .message = "Viewport framebuffer resized", .detail = "ready", .accent = .violet },
        .{ .level = "UI", .message = "Retained tree rebuilt", .detail = "clean", .accent = .accent },
    };
    for (logs) |log| {
        try logCard(state, rows, log);
    }
}

fn objectCard(state: *ui.Ui, parent: ui.NodeId) !ui.NodeId {
    const card = try ui.widgets.card(state, parent, .{ .height = .{ .px = 86 } });
    const row = try ui.widgets.row(state, card, .{
        .width = .fill,
        .height = .{ .px = 34 },
        .gap = 10,
    });
    _ = try ui.widgets.surface(state, row, .{
        .width = .{ .px = 34 },
        .height = .{ .px = 34 },
        .background = .violet_soft,
        .border = .violet,
        .border_width = 1,
        .radius = .card,
    });
    const labels = try ui.widgets.column(state, row, .{
        .width = .fill,
        .height = .fill,
        .gap = 2,
    });
    _ = try ui.widgets.text(state, labels, "Monkey Mesh", .{ .width = .fill, .size = 15 });
    _ = try ui.widgets.text(state, labels, "Entity ID 42", .{ .width = .fill, .color = .text_muted, .size = state.theme.font.small });
    _ = try ui.widgets.text(state, card, "Renderable scene object using the default orbit camera.", .{
        .width = .fill,
        .height = .fill,
        .padding = ui.Edges{ .top = 4 },
        .color = .text_dim,
        .size = state.theme.font.small,
    });
    return card;
}

fn inspectorSection(state: *ui.Ui, parent: ui.NodeId, title: []const u8, fields: []const InspectorField) !void {
    _ = try ui.widgets.sectionLabel(state, parent, title);
    const card = try ui.widgets.card(state, parent, .{
        .gap = 6,
        .padding = ui.Edges.all(8),
    });
    for (fields) |field| {
        try fieldRow(state, card, field);
    }
}

fn fieldRow(state: *ui.Ui, parent: ui.NodeId, field: InspectorField) !void {
    const row = try ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .{ .px = 28 },
        .gap = 8,
        .padding = ui.Edges{ .left = 8, .right = 8, .top = 5, .bottom = 5 },
        .background = .panel_soft,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .control,
    });
    _ = try ui.widgets.text(state, row, field.label, .{
        .width = .{ .px = 78 },
        .height = .fill,
        .color = .text_muted,
        .size = state.theme.font.small,
    });
    _ = try ui.widgets.text(state, row, field.value, .{
        .width = .fill,
        .height = .fill,
        .size = state.theme.font.small,
    });
}

fn sidebarRow(state: *ui.Ui, parent: ui.NodeId, item: SidebarItem) !void {
    const bg: ui.ColorRole = if (item.active) .control else .transparent;
    const stroke: ui.ColorRole = if (item.active) .stroke else .stroke_soft;
    const accent: ui.ColorRole = if (item.active) .accent else .stroke;
    const row = try ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .{ .px = 34 },
        .gap = 8,
        .padding = ui.Edges{ .left = 8, .right = 8, .top = 7, .bottom = 7 },
        .background = bg,
        .border = stroke,
        .border_width = if (item.active) 1 else 0,
        .radius = .control,
    });
    _ = try ui.widgets.surface(state, row, .{
        .width = .{ .px = 6 },
        .height = .{ .px = 6 },
        .margin = ui.Edges{ .top = 6 },
        .background = accent,
        .radius_px = 3,
    });
    _ = try ui.widgets.text(state, row, item.label, .{
        .width = .fill,
        .height = .fill,
        .color = if (item.active) .text else .text_dim,
        .size = state.theme.font.body,
    });
    if (item.detail.len != 0) {
        _ = try ui.widgets.text(state, row, item.detail, .{
            .width = .{ .px = if (item.active) 58 else 26 },
            .height = .fill,
            .color = .text_muted,
            .size = state.theme.font.tiny,
        });
    }
}

fn searchBox(state: *ui.Ui, parent: ui.NodeId, placeholder: []const u8) !ui.NodeId {
    const box = try ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .{ .px = 34 },
        .gap = 8,
        .padding = ui.Edges{ .left = 10, .right = 10, .top = 8, .bottom = 8 },
        .background = .shell,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .control,
    });
    _ = try ui.widgets.text(state, box, placeholder, .{
        .width = .fill,
        .height = .fill,
        .color = .text_muted,
        .size = state.theme.font.small,
    });
    return box;
}

fn statusCard(state: *ui.Ui, parent: ui.NodeId, title: []const u8, detail: []const u8) !ui.NodeId {
    const card = try ui.widgets.card(state, parent, .{ .height = .{ .px = 58 } });
    _ = try ui.widgets.text(state, card, title, .{ .width = .fill, .size = state.theme.font.body });
    _ = try ui.widgets.text(state, card, detail, .{
        .width = .fill,
        .padding = ui.Edges{ .top = 2 },
        .color = .text_muted,
        .size = state.theme.font.small,
    });
    return card;
}

fn logCard(state: *ui.Ui, parent: ui.NodeId, item: LogItem) !void {
    const card = try ui.widgets.card(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 4,
        .padding = ui.Edges.all(10),
        .surface = .panel,
    });
    const header = try ui.widgets.row(state, card, .{
        .width = .fill,
        .height = .{ .px = 18 },
        .gap = 8,
    });
    _ = try ui.widgets.surface(state, header, .{
        .width = .{ .px = 6 },
        .height = .{ .px = 6 },
        .margin = ui.Edges{ .top = 5 },
        .background = item.accent,
        .radius_px = 3,
    });
    _ = try ui.widgets.text(state, header, item.level, .{
        .width = .fill,
        .height = .fill,
        .color = item.accent,
        .size = state.theme.font.tiny,
    });
    _ = try ui.widgets.text(state, card, item.message, .{ .width = .fill, .size = state.theme.font.body });
    _ = try ui.widgets.text(state, card, item.detail, .{
        .width = .fill,
        .color = .text_muted,
        .size = state.theme.font.small,
    });
}

fn setNodeWidth(state: *ui.Ui, id: ui.NodeId, width: f32) void {
    if (state.tree.get(id)) |node| {
        node.style.width = .{ .px = @max(0, width) };
        node.dirty.layout = true;
    }
}

fn setNodeHeight(state: *ui.Ui, id: ui.NodeId, height: f32) void {
    if (state.tree.get(id)) |node| {
        node.style.height = .{ .px = @max(0, height) };
        node.dirty.layout = true;
    }
}

fn isSplitHighlighted(split: ui.DockNodeId, hovered: ?ui.DockNodeId, active: ?ui.DockNodeId) bool {
    if (active) |active_split| return active_split == split;
    if (hovered) |hovered_split| return hovered_split == split;
    return false;
}
