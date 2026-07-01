const ui = @import("zGUI");

pub const SceneInputCapture = struct {
    active: bool = false,

    pub fn accepts(
        self: *SceneInputCapture,
        event: anytype,
        viewport_rect: ui.Rect,
        mouse_pos: ui.Vec2,
        ui_capture: ui.InputCapture,
    ) bool {
        const mouse_in_viewport = viewport_rect.contains(mouse_pos);

        return switch (event) {
            .MouseMove => self.active or mouse_in_viewport,
            .MousePressed => pressed: {
                if (ui_capture.wants_mouse and !mouse_in_viewport) {
                    break :pressed false;
                }
                if (mouse_in_viewport) {
                    self.active = true;
                    break :pressed true;
                }
                break :pressed false;
            },
            .MouseReleased => released: {
                const was_active = self.active;
                self.active = false;
                break :released was_active or mouse_in_viewport;
            },
            .MouseScroll => scroll: {
                if (ui_capture.wants_mouse and !mouse_in_viewport and !self.active) {
                    break :scroll false;
                }
                break :scroll self.active or mouse_in_viewport;
            },
            .KeyPressed, .KeyReleased, .KeyRepeated => !ui_capture.wants_text_input and (self.active or mouse_in_viewport),
            .WindowResize, .FramebufferResize, .ContentScaleChange, .WindowClose => true,
            .CharInput => false,
        };
    }
};
