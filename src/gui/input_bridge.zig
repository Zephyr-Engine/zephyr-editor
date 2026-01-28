const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const ZEvent = runtime.ZEvent;
const Key = runtime.Key;
const MouseButton = runtime.MouseButton;
const GuiContext = zgui.GuiContext;
const zgui_window = zgui.window;

/// Translates zephyr-runtime events to zGUI input calls
pub const InputBridge = struct {
    gui_ctx: *GuiContext,

    pub fn init(gui_ctx: *GuiContext) InputBridge {
        return .{
            .gui_ctx = gui_ctx,
        };
    }

    /// Process a zephyr-runtime event and inject it into zGUI
    pub fn processEvent(self: *InputBridge, e: ZEvent) void {
        switch (e) {
            .MouseMove => |m| {
                self.gui_ctx.injectMouseMove(m.x, m.y);
            },
            .MousePressed => |btn| {
                const zgui_btn = mapMouseButton(btn);
                self.gui_ctx.injectMouseButton(zgui_btn, true);
            },
            .MouseReleased => |btn| {
                const zgui_btn = mapMouseButton(btn);
                self.gui_ctx.injectMouseButton(zgui_btn, false);
            },
            .MouseScroll => |s| {
                self.gui_ctx.injectScroll(s.x, s.y);
            },
            .KeyPressed => |k| {
                const zgui_key = mapKey(k);
                self.gui_ctx.injectKey(zgui_key, .press);
                self.updateModifiers(k, true);
            },
            .KeyReleased => |k| {
                const zgui_key = mapKey(k);
                self.gui_ctx.injectKey(zgui_key, .release);
                self.updateModifiers(k, false);
            },
            .KeyRepeated => |k| {
                const zgui_key = mapKey(k);
                self.gui_ctx.injectKey(zgui_key, .repeat);
            },
            .CharInput => |codepoint| {
                self.gui_ctx.injectChar(codepoint);
            },
            .WindowResize => |size| {
                self.gui_ctx.setWindowSize(@floatFromInt(size.width), @floatFromInt(size.height));
            },
            .FramebufferResize => {},
            .ContentScaleChange => |scale| {
                self.gui_ctx.updateContentScale(scale.x, scale.y);
            },
            .WindowClose => {},
        }
    }

    fn updateModifiers(self: *InputBridge, key: Key, pressed: bool) void {
        const ctrl = self.gui_ctx.input.ctrl_pressed;
        const alt = self.gui_ctx.input.alt_pressed;
        const shift = self.gui_ctx.input.shift_pressed;
        const super = self.gui_ctx.input.super_pressed;

        switch (key) {
            .LeftControl, .RightControl => self.gui_ctx.injectModifiers(pressed, alt, shift, super),
            .LeftAlt, .RightAlt => self.gui_ctx.injectModifiers(ctrl, pressed, shift, super),
            .LeftShift, .RightShift => self.gui_ctx.injectModifiers(ctrl, alt, pressed, super),
            .LeftSuper, .RightSuper => self.gui_ctx.injectModifiers(ctrl, alt, shift, pressed),
            else => {},
        }
    }

    fn mapMouseButton(btn: MouseButton) zgui_window.MouseButton {
        return switch (btn) {
            .Left => .left,
            .Right => .right,
            .Middle => .middle,
            else => .left,
        };
    }

    fn mapKey(key: Key) c_int {
        // GLFW key codes match between zephyr-runtime and zGUI
        return @intFromEnum(key);
    }
};
