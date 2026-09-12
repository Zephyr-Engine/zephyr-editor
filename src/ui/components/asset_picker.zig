const fusion = @import("fusion_runtime");
const zimp = @import("zimp");
const ui = @import("zGUI");
const std = @import("std");

pub const AssetPicker = struct {
    const popup_width: f32 = 240;
    const max_visible_items: usize = 8;
    const chevron_down_optical_offset: f32 = 2;
    const chevron_up_optical_offset: f32 = 0;
    const none_label = "(none)";

    allocator: std.mem.Allocator,
    button: ui.NodeId,
    button_label: ui.NodeId,
    chevron: ui.NodeId,
    overlay_host: ui.NodeId,
    list: ui.SelectionList,
    selected: ?zimp.AssetId,
    ids: std.ArrayList(zimp.AssetId) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        overlay_host: ui.NodeId,
        manifest: *const fusion.RuntimeAssetManifest,
        kind: zimp.AssetKind,
        selected: zimp.AssetId,
    ) !AssetPicker {
        const button = try ui.widgets.button(state, parent, "", state.theme.style(.{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.control_height },
            .direction = .row,
            .padding = .{
                .left = state.theme.space.lg,
                .right = state.theme.space.lg,
            },
            .background = .control,
            .hover_background = .interaction_hover,
            .pressed_background = .interaction_pressed,
            .border = .stroke,
            .hover_border = .accent_border,
            .pressed_border = .accent_border_strong,
            .border_width = 1,
            .radius = .control,
        }));
        errdefer state.destroySubtree(button);

        const button_label = try ui.widgets.text(state, button, selectedLabel(manifest, selected), .{
            .width = .fill,
            .height = .fill,
            .padding = .{ .top = state.centeredTextTop(state.theme.metrics.control_height, state.theme.font.body) },
            .color = .text_dim,
            .size = state.theme.font.body,
        });
        const chevron = try ui.widgets.text(state, button, "⌄", .{
            .width = .hug,
            .height = .fill,
            .padding = .{ .top = state.centeredTextTop(state.theme.metrics.control_height, state.theme.font.body) - chevron_down_optical_offset },
            .color = .text_muted,
            .size = state.theme.font.body,
        });

        var list = try ui.SelectionList.initWithOptions(allocator, state, overlay_host, .{
            .width = popup_width,
            .max_visible_items = max_visible_items,
            .search = .{
                .placeholder = "Search assets",
                .empty_label = "No matching assets",
            },
        });
        errdefer list.deinit(state);

        var ids: std.ArrayList(zimp.AssetId) = .empty;
        errdefer ids.deinit(allocator);
        var labels: std.ArrayList([]const u8) = .empty;
        defer labels.deinit(allocator);

        try ids.append(allocator, .zero);
        for (manifest.entries) |*entry| {
            if (entry.kind != kind) continue;
            try ids.append(allocator, entry.id);
            try labels.append(allocator, assetLabel(entry.cooked_path));
        }
        try list.setItems(state, labels.items);

        return .{
            .allocator = allocator,
            .button = button,
            .button_label = button_label,
            .chevron = chevron,
            .overlay_host = overlay_host,
            .list = list,
            .selected = if (selected.isZero()) null else selected,
            .ids = ids,
        };
    }

    pub fn deinit(self: *AssetPicker, state: *ui.Ui) void {
        self.list.deinit(state);
        state.destroySubtree(self.button);
        self.ids.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn update(self: *AssetPicker, state: *ui.Ui) !?zimp.AssetId {
        if (state.activated(self.button)) {
            if (self.list.open) {
                try self.list.close(state);
                try self.setChevron(state, false);
            } else {
                const button_bounds = state.bounds(self.button) orelse return null;
                const overlay_bounds = state.bounds(self.overlay_host) orelse return null;
                try self.list.showAnchored(
                    state,
                    button_bounds,
                    overlay_bounds,
                    state.theme.space.xs,
                );
                try self.setChevron(state, true);
            }
            return null;
        }

        const was_open = self.list.open;
        const selection = try self.list.update(state);
        if (was_open and !self.list.open) {
            try self.setChevron(state, false);
        }

        const index = selection orelse return null;
        const id = self.ids.items[index];
        self.selected = if (id.isZero()) null else id;
        try state.setText(self.button_label, self.list.labelAt(index) orelse return error.InvalidAssetIndex);
        return id;
    }

    pub fn labelFor(manifest: *const fusion.RuntimeAssetManifest, id: zimp.AssetId) []const u8 {
        const entry = manifest.byId(id) orelse return "(missing asset)";
        return assetLabel(entry.cooked_path);
    }

    fn selectedLabel(manifest: *const fusion.RuntimeAssetManifest, selected: zimp.AssetId) []const u8 {
        return if (selected.isZero()) none_label else labelFor(manifest, selected);
    }

    fn setChevron(self: *AssetPicker, state: *ui.Ui, open: bool) !void {
        try state.setText(self.chevron, if (open) "⌃" else "⌄");
        var style = state.nodeStyle(self.chevron) orelse return error.InvalidNode;
        const optical_offset = if (open) chevron_up_optical_offset else chevron_down_optical_offset;
        style.padding.top = state.centeredTextTop(state.theme.metrics.control_height, state.theme.font.body) - optical_offset;
        try state.setStyle(self.chevron, style);
    }

    fn assetLabel(cooked_path: []const u8) []const u8 {
        return std.fs.path.stem(cooked_path);
    }
};
