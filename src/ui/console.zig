const ui = @import("zGUI_retained");

pub fn build(state: *ui.Ui, parent: ui.NodeId) !ui.NodeId {
    const panel = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 8,
        .padding = ui.Edges{ .left = 12, .right = 12, .top = 10, .bottom = 10 },
        .background = .shell,
        .border = .stroke_soft,
        .border_edges = ui.Edges{ .top = 1 },
    });

    const header = try ui.widgets.row(state, panel, .{
        .width = .fill,
        .height = .{ .px = 28 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, header, "Console", .{
        .width = .{ .px = 72 },
        .height = .fill,
        .padding = ui.Edges{ .top = 6 },
        .size = 14,
    });

    return panel;
}
