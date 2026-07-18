const ui = @import("zGUI");

/// Decides which runtime events reach the 3D scene while the editor UI is
/// active: pointer events inside the viewport rect, plus follow-through for
/// drags that started there. (Formerly ui.zephyr_runtime.SceneInputCapture,
/// removed from zGUI when scene integration moved out of the library.)
pub const SceneInputCapture = struct {
    active: bool = false,

    /// `ui_owns_mouse` should be true while the dock space is using the
    /// pointer (hovering or dragging a resize handle, dragging a tab); the
    /// handle hit strips overlap the viewport rect by half their thickness,
    /// so without it a resize drag would also start a scene camera drag.
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
            .KeyPressed, .KeyReleased, .KeyRepeated => self.active or scene_target,
            .WindowResize, .FramebufferResize, .ContentScaleChange, .WindowClose => true,
            .CharInput => false,
        };
    }
};

pub fn processSceneEvents(
    app: anytype,
    runtime_events: anytype,
    viewport_rect: ui.Rect,
    mouse_pos: ui.Vec2,
    capture: *SceneInputCapture,
    ui_owns_mouse: bool,
) !void {
    for (runtime_events) |event| {
        if (capture.accepts(event, viewport_rect, mouse_pos, ui_owns_mouse)) {
            try app.processEvent(event);
        }
    }
}
