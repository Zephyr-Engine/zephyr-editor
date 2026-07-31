const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

pub const SceneInputCapture = struct {
    active: bool = false,

    pub fn accepts(self: *SceneInputCapture, event: anytype, viewport_rect: ui.Rect, mouse_pos: ui.Vec2, ui_owns_mouse: bool) bool {
        const scene_target = viewport_rect.contains(mouse_pos) and !ui_owns_mouse;
        return switch (event) {
            .MouseMove => true,
            .MousePressed => pressed: {
                if (scene_target) {
                    self.active = true;
                    break :pressed true;
                }
                break :pressed false;
            },
            .MouseReleased => released: {
                const was_active = self.active;
                self.active = false;
                break :released was_active or scene_target;
            },
            .MouseScroll => self.active or scene_target,
            .KeyReleased => true,
            .KeyPressed, .KeyRepeated => self.active or scene_target,
            .WindowResize, .FramebufferResize, .ContentScaleChange, .WindowClose => true,
            .CharInput => false,
        };
    }
};

pub fn processSceneEvents(
    input: *zp.Input,
    runtime_events: []const zp.ZEvent,
    viewport_rect: ui.Rect,
    mouse_pos: ui.Vec2,
    capture: *SceneInputCapture,
    ui_owns_mouse: bool,
) void {
    for (runtime_events) |event| {
        if (capture.accepts(event, viewport_rect, mouse_pos, ui_owns_mouse)) {
            input.applyEvent(event);
        }
    }
}
