const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const EditorHints = zimp.scene.EditorFieldHints;

pub const IntField = struct {
    field: ui.NumericField,
    slider: ?ui.Slider = null,
    value: i32,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: i32,
        hints: EditorHints,
    ) !IntField {
        const host = try controlHost(state, parent, hasSlider(hints));
        errdefer if (host != parent) state.destroySubtree(host);
        var slider: ?ui.Slider = null;
        if (hasSlider(hints)) slider = try ui.Slider.init(state, host, sliderOptions(hints));
        return .{
            .field = try ui.NumericField.initI32(allocator, state, host, value, options(state, hints, slider != null)),
            .slider = slider,
            .value = value,
        };
    }

    pub fn deinit(self: *IntField, state: *ui.Ui) void {
        self.field.deinit(state);
        if (self.slider) |*slider| slider.deinit(state);
    }

    pub fn update(self: *IntField, state: *ui.Ui, hints: EditorHints) !bool {
        const before = self.value;
        var changed = false;
        if (self.slider) |*slider| {
            var value: f32 = @floatFromInt(self.value);
            if (try slider.update(state, &value, sliderOptions(hints))) {
                self.value = @intFromFloat(@round(value));
                try syncText(&self.field, state, self.value);
                changed = true;
            }
        }
        const result = try self.field.updateI32(state, &self.value, options(state, hints, self.slider != null));
        if (result.changed and !result.committed) {
            if (previewI32(self.field.text.text(), hints)) |value| self.value = value;
        }
        return changed or self.value != before;
    }
};

pub const UintField = struct {
    field: ui.NumericField,
    slider: ?ui.Slider = null,
    value: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: u32,
        hints: EditorHints,
    ) !UintField {
        const host = try controlHost(state, parent, hasSlider(hints));
        errdefer if (host != parent) state.destroySubtree(host);
        var slider: ?ui.Slider = null;
        if (hasSlider(hints)) slider = try ui.Slider.init(state, host, sliderOptions(hints));
        return .{
            .field = try ui.NumericField.initU32(allocator, state, host, value, options(state, hints, slider != null)),
            .slider = slider,
            .value = value,
        };
    }

    pub fn deinit(self: *UintField, state: *ui.Ui) void {
        self.field.deinit(state);
        if (self.slider) |*slider| slider.deinit(state);
    }

    pub fn update(self: *UintField, state: *ui.Ui, hints: EditorHints) !bool {
        const before = self.value;
        var changed = false;
        if (self.slider) |*slider| {
            var value: f32 = @floatFromInt(self.value);
            if (try slider.update(state, &value, sliderOptions(hints))) {
                self.value = @intFromFloat(@max(0, @round(value)));
                try syncText(&self.field, state, self.value);
                changed = true;
            }
        }
        const result = try self.field.updateU32(state, &self.value, options(state, hints, self.slider != null));
        if (result.changed and !result.committed) {
            if (previewU32(self.field.text.text(), hints)) |value| self.value = value;
        }
        return changed or self.value != before;
    }
};

pub const FloatField = struct {
    field: ui.NumericField,
    slider: ?ui.Slider = null,
    value: f32,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: f32,
        hints: EditorHints,
    ) !FloatField {
        const host = try controlHost(state, parent, hasSlider(hints));
        errdefer if (host != parent) state.destroySubtree(host);
        var slider: ?ui.Slider = null;
        if (hasSlider(hints)) slider = try ui.Slider.init(state, host, sliderOptions(hints));
        return .{
            .field = try ui.NumericField.initF32(allocator, state, host, value, options(state, hints, slider != null)),
            .slider = slider,
            .value = value,
        };
    }

    pub fn deinit(self: *FloatField, state: *ui.Ui) void {
        self.field.deinit(state);
        if (self.slider) |*slider| slider.deinit(state);
    }

    pub fn update(self: *FloatField, state: *ui.Ui, hints: EditorHints) !bool {
        const before = self.value;
        var changed = false;
        if (self.slider) |*slider| {
            changed = try slider.update(state, &self.value, sliderOptions(hints));
            if (changed) try syncText(&self.field, state, self.value);
        }
        const result = try self.field.updateF32(state, &self.value, options(state, hints, self.slider != null));
        if (result.changed and !result.committed) {
            if (previewF32(self.field.text.text(), hints)) |value| self.value = value;
        }
        return changed or self.value != before;
    }
};

pub fn options(state: *const ui.Ui, hints: EditorHints, compact: bool) ui.NumericOptions {
    return .{
        .min = hints.min,
        .max = hints.max,
        .step = hints.step,
        .width = if (compact) .{ .px = compactWidth(state) } else .fill,
    };
}

/// A compact field sits beside a slider, so it has to hold a full float such as
/// "0.7853982" plus the field's left inset and its trailing gutter. Deriving it
/// from the type scale keeps the value from spilling when the theme grows.
fn compactWidth(state: *const ui.Ui) f32 {
    const glyphs = 9.0;
    const glyph_width = state.theme.font.body * 0.55;
    return @round(glyphs * glyph_width) + state.theme.space.lg * 2 + state.theme.metrics.control_height;
}

pub fn previewF32(text: []const u8, hints: EditorHints) ?f32 {
    return applyHints(std.fmt.parseFloat(f32, text) catch return null, hints);
}

fn previewI32(text: []const u8, hints: EditorHints) ?i32 {
    const parsed = std.fmt.parseInt(i32, text, 10) catch return null;
    const hinted = applyHints(@floatFromInt(parsed), hints) orelse return null;
    return @intFromFloat(std.math.clamp(
        @round(hinted),
        @as(f32, @floatFromInt(std.math.minInt(i32))),
        @as(f32, @floatFromInt(std.math.maxInt(i32))),
    ));
}

fn previewU32(text: []const u8, hints: EditorHints) ?u32 {
    const parsed = std.fmt.parseInt(u32, text, 10) catch return null;
    const hinted = applyHints(@floatFromInt(parsed), hints) orelse return null;
    return @intFromFloat(std.math.clamp(
        @round(hinted),
        0,
        @as(f32, @floatFromInt(std.math.maxInt(u32))),
    ));
}

fn applyHints(input: f32, hints: EditorHints) ?f32 {
    if (!std.math.isFinite(input)) return null;
    var value = input;
    if (hints.min) |minimum| value = @max(minimum, value);
    if (hints.max) |maximum| value = @min(maximum, value);
    if (hints.step) |step| {
        if (step <= 0 or !std.math.isFinite(step)) return null;
        value = @round(value / step) * step;
        if (hints.min) |minimum| value = @max(minimum, value);
        if (hints.max) |maximum| value = @min(maximum, value);
    }
    return value;
}

fn controlHost(state: *ui.Ui, parent: ui.NodeId, with_slider: bool) !ui.NodeId {
    if (!with_slider) return parent;
    return ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .{ .px = state.theme.metrics.control_height },
        .gap = state.theme.space.sm,
    });
}

fn syncText(field: *ui.NumericField, state: *ui.Ui, value: anytype) !void {
    var buffer: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, "{d}", .{value});
    try field.text.setTextContent(state, text, 64);
}

fn hasSlider(hints: EditorHints) bool {
    return hints.slider and hints.min != null and hints.max != null and hints.min.? < hints.max.?;
}

fn sliderOptions(hints: EditorHints) ui.SliderOptions {
    return .{
        .min = hints.min.?,
        .max = hints.max.?,
        .step = hints.step orelse 0,
    };
}

test "numeric previews apply valid edits immediately and tolerate incomplete input" {
    const hints: EditorHints = .{ .min = 0, .max = 10, .step = 0.5 };
    try std.testing.expectEqual(@as(?f32, 1.5), previewF32("1.6", hints));
    try std.testing.expectEqual(@as(?i32, 4), previewI32("4", hints));
    try std.testing.expectEqual(@as(?u32, 10), previewU32("12", hints));
    try std.testing.expect(previewF32("-", hints) == null);
    try std.testing.expect(previewF32("nan", hints) == null);
}

test "numeric controls emit live values before focus loss" {
    var state = try ui.Ui.init(std.testing.allocator);
    defer state.deinit();
    var field = try FloatField.init(std.testing.allocator, &state, state.rootNode(), 1, .{});
    defer field.deinit(&state);

    state.requestFocus(field.field.text.root_node);
    try state.beginFrame(.{ .window_size = .{ .x = 200, .y = 50 } });
    _ = try field.update(&state, .{});
    try state.endFrame();

    try state.beginFrame(.{
        .events = &.{ .{ .key_down = .backspace }, .{ .text_input = "2" } },
        .window_size = .{ .x = 200, .y = 50 },
    });
    try std.testing.expect(try field.update(&state, .{}));
    try std.testing.expectEqual(@as(f32, 2), field.value);
}
