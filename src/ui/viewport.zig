const zp = @import("zephyr_runtime");
const std = @import("std");
const ui = @import("zGUI");

const Command = @import("../editor/command.zig").Command;

const toolbar_commands = [_]Command{ .play, .pause, .stop };

pub const Nodes = struct {
    root: ui.NodeId,
    image: ui.NodeId,
    control_buttons: [toolbar_commands.len]ui.NodeId,
    stats_card: ui.NodeId,
    stats_label: ui.NodeId,
};

/// Image resources for the toolbar. The toolbar itself emits commands and does
/// not own editor state.
pub const ControlIcons = struct {
    play: ui.TextureHandle,
    pause: ui.TextureHandle,
    stop: ui.TextureHandle,

    fn forCommand(self: ControlIcons, command: Command) ui.TextureHandle {
        return switch (command) {
            .play => self.play,
            .pause => self.pause,
            .stop => self.stop,
        };
    }
};

pub const Commands = struct {
    values: [toolbar_commands.len]Command = undefined,
    len: usize = 0,

    fn append(self: *Commands, command: Command) void {
        std.debug.assert(self.len < self.values.len);
        self.values[self.len] = command;
        self.len += 1;
    }

    pub fn slice(self: *const Commands) []const Command {
        return self.values[0..self.len];
    }
};

pub fn build(state: *ui.Ui, parent: ui.NodeId, icons: ControlIcons) !Nodes {
    const root = try ui.widgets.surface(state, parent, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .viewport,
    });

    const image = try ui.widgets.image(state, root, .{
        .texture = .none,
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
        .interactive = false,
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

    var toolbar_style = state.nodeStyle(toolbar).?;
    toolbar_style.background = ui.Color.rgba(17, 18, 22, 232);
    toolbar_style.border_color = ui.Color.rgba(255, 255, 255, 24);
    try state.setStyle(toolbar, toolbar_style);

    _ = try ui.widgets.spacer(state, toolbar_row);
    var control_buttons: [toolbar_commands.len]ui.NodeId = undefined;
    for (toolbar_commands, 0..) |command, index| {
        control_buttons[index] = try controlButton(state, toolbar, icons.forCommand(command));
    }

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

    var card_style = state.nodeStyle(stats_card).?;
    card_style.background = ui.Color.rgba(30, 30, 36, 220);
    try state.setStyle(stats_card, card_style);
    try state.setVisible(stats_card, false);

    return .{
        .root = root,
        .image = image,
        .control_buttons = control_buttons,
        .stats_card = stats_card,
        .stats_label = stats_label,
    };
}

pub fn controlsOwnMouse(state: *const ui.Ui, nodes: Nodes) bool {
    for (nodes.control_buttons) |button| {
        if (controlInteracting(state, button)) return true;
    }
    return false;
}

/// Collects every command requested by this frame's toolbar interaction.
/// Add a button by declaring its command and icon, then adding it to
/// `toolbar_commands`; editor-state wiring is not needed here.
pub fn commands(state: *const ui.Ui, nodes: Nodes) Commands {
    var result: Commands = .{};
    for (toolbar_commands, nodes.control_buttons) |command, button| {
        if (state.clicked(button)) result.append(command);
    }
    return result;
}

fn controlInteracting(state: *const ui.Ui, id: ui.NodeId) bool {
    const interaction = state.interaction(id);
    return interaction.hovered or interaction.active;
}

fn controlButton(state: *ui.Ui, parent: ui.NodeId, texture: ui.TextureHandle) !ui.NodeId {
    const button = try ui.widgets.iconButton(state, parent, .{
        .texture = texture,
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

    var button_style = state.nodeStyle(button).?;
    button_style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    button_style.pressed_background = ui.Color.rgba(255, 255, 255, 30);
    try state.setStyle(button, button_style);

    return button;
}

pub fn setTexture(state: *ui.Ui, image: ui.NodeId, texture: ui.TextureHandle) !void {
    ui.widgets.setImage(state, image, .{
        .texture = texture,
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .tint = ui.Color.rgba(255, 255, 255, 255),
    });
}

pub fn setStats(state: *ui.Ui, nodes: Nodes, buffer: []u8, stats: ?zp.DebugStats) !void {
    const snapshot = stats orelse {
        try state.setVisible(nodes.stats_card, false);
        try state.setVisible(nodes.stats_label, false);
        return;
    };

    const text = if (snapshot.gpu_time_ms) |gpu_time_ms|
        std.fmt.bufPrint(buffer, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  {d:.2} ms", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
            gpu_time_ms,
        }) catch return error.StatsBufferTooSmall
    else
        std.fmt.bufPrint(buffer, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  --", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
        }) catch return error.StatsBufferTooSmall;

    try state.setVisible(nodes.stats_card, true);
    try state.setVisible(nodes.stats_label, true);
    try state.setText(nodes.stats_label, text);
}

test "toolbar command buffers preserve action order" {
    var buffer: Commands = .{};
    buffer.append(.play);
    buffer.append(.stop);

    try std.testing.expectEqualSlices(Command, &.{ .play, .stop }, buffer.slice());
}
