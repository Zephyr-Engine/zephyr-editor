const zp = @import("zephyr_runtime");
const std = @import("std");
const ui = @import("zGUI");

const PlayState = @import("../state/play_state.zig").PlayState;

pub const Nodes = struct {
    root: ui.NodeId,
    image: ui.NodeId,
    play_button: ui.NodeId,
    pause_button: ui.NodeId,
    stop_button: ui.NodeId,
    stats_card: ui.NodeId,
    stats_label: ui.NodeId,
};

pub const ControlTextures = struct {
    play: u32,
    pause: u32,
    stop: u32,

    state: PlayState,
};

pub fn build(state: *ui.Ui, parent: ui.NodeId, controls: *ControlTextures) !Nodes {
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

    const toolbar_row = try ui.widgets.row(state, root, .{
        .width = .fill,
        .height = .{ .px = 52 },
        .padding = .{ .top = 9 },
        .background = .transparent,
    });

    _ = try ui.widgets.spacer(state, toolbar_row);
    const toolbar = try ui.widgets.row(state, toolbar_row, .{
        .width = .{ .px = 98 },
        .height = .{ .px = 36 },
        .gap = 2,
        .padding = .{ .left = 5, .right = 5, .top = 4, .bottom = 4 },
        .background = .shell,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .pill,
    });

    const toolbar_node = state.tree.get(toolbar).?;
    toolbar_node.style.background = ui.Color.rgba(17, 18, 22, 232);
    toolbar_node.style.border_color = ui.Color.rgba(255, 255, 255, 24);

    _ = try ui.widgets.spacer(state, toolbar_row);
    const play_button = try controlButton(state, toolbar, controls.play);
    const pause_button = try controlButton(state, toolbar, controls.pause);
    const stop_button = try controlButton(state, toolbar, controls.stop);

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
        .play_button = play_button,
        .pause_button = pause_button,
        .stop_button = stop_button,
        .stats_card = stats_card,
        .stats_label = stats_label,
    };
}

pub fn controlsOwnMouse(state: *const ui.Ui, nodes: Nodes) bool {
    return isControl(nodes, state.input.hovered) or isControl(nodes, state.input.active);
}

pub fn processControls(state: *const ui.Ui, nodes: Nodes, controls: *ControlTextures) void {
    if (ui.input.buttonClicked(state.input, nodes.play_button)) {
        controls.state = controls.state.transition(.Play);
    }

    if (ui.input.buttonClicked(state.input, nodes.pause_button)) {
        controls.state = controls.state.transition(.Pause);
    }

    if (ui.input.buttonClicked(state.input, nodes.stop_button)) {
        controls.state = controls.state.transition(.Stop);
    }
}

fn isControl(nodes: Nodes, id: ui.NodeId) bool {
    return id == nodes.play_button or id == nodes.pause_button or id == nodes.stop_button;
}

fn controlButton(state: *ui.Ui, parent: ui.NodeId, texture_id: u32) !ui.NodeId {
    const button = try ui.widgets.iconButton(state, parent, .{
        .texture_id = texture_id,
        .style = state.theme.style(.{
            .width = .{ .px = 28 },
            .height = .{ .px = 28 },
            .padding = .{ .left = 4, .right = 4, .top = 4, .bottom = 4 },
            .background = .transparent,
            .border = .transparent,
            .radius = .control,
        }),
        .tint = ui.Color.rgba(194, 198, 207, 255),
    });

    const node = state.tree.get(button).?;
    node.style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    node.style.pressed_background = ui.Color.rgba(255, 255, 255, 30);

    return button;
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
