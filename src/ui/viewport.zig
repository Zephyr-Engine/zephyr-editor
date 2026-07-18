const std = @import("std");
const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

pub const Nodes = struct {
    root: ui.NodeId,
    image: ui.NodeId,
    stats_card: ui.NodeId,
    stats_label: ui.NodeId,
};

pub fn build(state: *ui.Ui, parent: ui.NodeId) !Nodes {
    const root = try ui.widgets.surface(state, parent, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .viewport,
    });
    const image = try ui.widgets.image(state, root, .{
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

    const stats_row = try ui.widgets.row(state, root, .{
        .width = .fill,
        .height = .{ .px = 82 },
        .padding = .{ .top = 10, .right = 10 },
        .background = .transparent,
    });
    _ = try ui.widgets.spacer(state, stats_row);
    const stats_card = try ui.widgets.surface(state, stats_row, .{
        .width = .{ .px = 120 },
        .height = .{ .px = 58 },
        .padding = .{ .left = 10, .right = 10, .top = 8, .bottom = 8 },
        .background = .panel_soft,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .control,
    });
    const stats_label = try ui.widgets.text(state, stats_card, "", .{
        .width = .fill,
        .height = .fill,
        .color = .text,
        .size = state.theme.font.small,
    });
    const card_node = state.tree.get(stats_card).?;
    card_node.style.background = ui.Color.rgba(30, 30, 36, 220);
    card_node.flags.visible = false;

    return .{
        .root = root,
        .image = image,
        .stats_card = stats_card,
        .stats_label = stats_label,
    };
}

pub fn setTexture(state: *ui.Ui, image: ui.NodeId, texture_id: u32) void {
    ui.widgets.setImage(state, image, .{
        .texture_id = texture_id,
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .tint = ui.Color.rgba(255, 255, 255, 255),
    });
}

pub fn setStats(state: *ui.Ui, nodes: Nodes, buffer: []u8, stats: ?zp.DebugStats) void {
    const snapshot = stats orelse {
        setVisible(state, nodes.stats_card, false);
        setVisible(state, nodes.stats_label, false);
        return;
    };

    const text = if (snapshot.gpu_time_ms) |gpu_time_ms|
        std.fmt.bufPrint(buffer, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  {d:.2} ms", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
            gpu_time_ms,
        }) catch return
    else
        std.fmt.bufPrint(buffer, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  --", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
        }) catch return;

    setVisible(state, nodes.stats_card, true);
    setVisible(state, nodes.stats_label, true);
    state.tree.setText(nodes.stats_label, text) catch return;
}

fn setVisible(state: *ui.Ui, id: ui.NodeId, visible: bool) void {
    const node = state.tree.get(id) orelse return;
    if (node.flags.visible == visible) return;
    node.flags.visible = visible;
    node.dirty.layout = true;
    node.dirty.paint = true;
}
