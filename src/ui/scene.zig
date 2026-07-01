const ui = @import("zGUI");

const panel_vertical_inset: f32 = 10;

pub fn build(state: *ui.Ui, parent: ui.NodeId) !ui.NodeId {
    const panel = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 10,
        .padding = ui.Edges{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .margin = ui.Edges{ .top = panel_vertical_inset, .bottom = panel_vertical_inset },
        .background = .panel,
        .radius_corners = ui.CornerRadii{
            .top_right = state.theme.radius(.card),
            .bottom_right = state.theme.radius(.card),
        },
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

    return panel;
}
