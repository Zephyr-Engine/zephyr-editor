const std = @import("std");
const ui = @import("zGUI");
const fusion = @import("fusion_runtime");

pub const ViewportStats = struct {
    card: ui.NodeId,
    label: ui.NodeId,
    text: [128]u8 = undefined,
    visible: bool = false,

    pub fn init(state: *ui.Ui, parent: ui.NodeId) !ViewportStats {
        // Size the card to three lines of the theme's small type so it keeps
        // its proportions when the type scale changes.
        const card_height = @round(state.textLineHeight(state.theme.font.small) * 3 +
            state.theme.space.md * 2);
        const placement = try ui.widgets.row(state, parent, .{
            .width = .fill,
            .height = .{ .px = card_height + state.theme.space.lg * 2 },
            .padding = .{ .top = state.theme.space.lg, .right = state.theme.space.lg },
            .background = .transparent,
        });
        errdefer state.destroySubtree(placement);
        _ = try ui.widgets.spacer(state, placement);
        const card = try ui.widgets.surface(state, placement, .{
            .width = .{ .px = 128 },
            .height = .{ .px = card_height },
            .padding = .{
                .left = state.theme.space.lg,
                .right = state.theme.space.lg,
                .top = state.theme.space.md,
                .bottom = state.theme.space.md,
            },
            .background = .overlay,
            .border = .overlay_stroke,
            .border_width = 1,
            .radius = .control,
        });
        const label = try ui.widgets.text(state, card, "", .{
            .width = .fill,
            .height = .fill,
            .color = .text,
            .size = state.theme.font.small,
        });
        try state.setVisible(card, false);
        return .{ .card = card, .label = label };
    }

    pub fn update(self: *ViewportStats, state: *ui.Ui, snapshot: ?fusion.DebugStats) !void {
        const stats = snapshot orelse {
            if (self.visible) {
                try state.setVisible(self.card, false);
                self.visible = false;
            }
            return;
        };

        const text = if (stats.gpu_time_ms) |gpu_time_ms|
            std.fmt.bufPrint(&self.text, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  {d:.2} ms", .{
                stats.fps,
                stats.frame_time_ms,
                stats.cpu_time_ms,
                gpu_time_ms,
            }) catch return error.StatsBufferTooSmall
        else
            std.fmt.bufPrint(&self.text, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  --", .{
                stats.fps,
                stats.frame_time_ms,
                stats.cpu_time_ms,
            }) catch return error.StatsBufferTooSmall;

        if (!self.visible) {
            try state.setVisible(self.card, true);
            self.visible = true;
        }
        try state.setText(self.label, text);
    }
};
