const ui = @import("zGUI");

pub fn build(state: *ui.Ui, parent: ui.NodeId) !ui.NodeId {
    return ui.widgets.image(state, parent, .{
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
}

pub fn setTexture(state: *ui.Ui, image: ui.NodeId, texture_id: u32) void {
    ui.widgets.setImage(state, image, .{
        .texture_id = texture_id,
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .tint = ui.Color.rgba(255, 255, 255, 255),
    });
}
