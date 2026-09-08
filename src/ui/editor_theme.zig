const ui = @import("zGUI");

// A violet-primary dark theme. The structure follows Nocturne
// (https://github.com/starside-io/nocturne) — near-black stacked surfaces, one
// accent reserved for focus and selection — but the values are sampled from the
// reference editor screenshot, which is softer and several stops lighter than
// Nocturne's neon spec: muted lavender accent, cool blue-grey plates, gently
// rounded corners.
//
// Raw palette. Product code reads the semantic roles below, never these.

// Surfaces — a cool blue-grey ramp centred on the reference's dominant #22232f.
const well = ui.Color.rgba(24, 24, 33, 255); // #181821  inset input surface
const ink_950 = ui.Color.rgba(20, 21, 29, 255); // #14151d
const ink_900 = ui.Color.rgba(26, 27, 36, 255); // #1a1b24
const ink_800 = ui.Color.rgba(34, 35, 47, 255); // #22232f  dominant panel plate
const ink_700 = ui.Color.rgba(39, 40, 53, 255); // #272835
const ink_600 = ui.Color.rgba(44, 45, 59, 255); // #2c2d3b
const ink_500 = ui.Color.rgba(50, 51, 66, 255); // #323342
const ink_400 = ui.Color.rgba(56, 57, 74, 255); // #38394a
const line = ui.Color.rgba(61, 63, 80, 255); // #3d3f50
const line_soft = ui.Color.rgba(46, 47, 58, 255); // #2e2f3a

// Text — four stops, sampled from headings down through metadata.
const text_bright = ui.Color.rgba(226, 229, 241, 255); // #e2e5f1
const text_body = ui.Color.rgba(206, 210, 228, 255); // #ced2e4
const text_second = ui.Color.rgba(177, 181, 201, 255); // #b1b5c9
const text_third = ui.Color.rgba(146, 150, 170, 255); // #9296aa

// Accent — the muted lavender carrying focus, selection and primary work.
const violet = ui.Color.rgba(144, 131, 216, 255); // #9083d8
const violet_bright = ui.Color.rgba(209, 205, 253, 255); // #d1cdfd
const violet_hot = ui.Color.rgba(163, 148, 255, 255); // #a394ff
const violet_fill = ui.Color.rgba(68, 61, 105, 255); // #443d69  chip / badge fill
const violet_well = ui.Color.rgba(55, 50, 83, 255); // #37325 3  active segment fill

// Status — held at the palette's low saturation so nothing outshouts the accent.
const amber = ui.Color.rgba(223, 194, 139, 255); // #dfc28b
const rose = ui.Color.rgba(223, 152, 152, 255); // #df9898
const sage = ui.Color.rgba(140, 205, 160, 255); // #8ccda0

pub fn theme() ui.Theme {
    var value = ui.theme.fusion_dark;

    // Elevation ascends app -> control. `shell` carries the docked panels and is
    // the surface the eye spends most time on, so it sits on the reference plate.
    value.palette.app = ink_900;
    value.palette.shell = ink_800;
    value.palette.panel = ink_700;
    value.palette.panel_soft = ink_600;
    value.palette.card = ink_500;
    // Controls are sunken wells, not raised chips: inputs read as cut into the
    // panel, which is what lets the small axis letters hold their colour.
    value.palette.control = well;
    // The viewport frame stays the darkest surface so scene content dominates.
    value.palette.viewport = ink_950;

    value.palette.stroke = line;
    value.palette.stroke_soft = line_soft;
    value.palette.overlay = ui.Color.rgba(26, 27, 36, 242);
    value.palette.overlay_soft = ui.Color.rgba(34, 35, 47, 234);
    value.palette.overlay_stroke = ui.Color.rgba(206, 210, 228, 30);
    value.palette.interaction_hover = ui.Color.rgba(206, 210, 228, 18);
    // Presses flash the accent rather than lifting to grey.
    value.palette.interaction_pressed = ui.Color.rgba(144, 131, 216, 40);

    value.palette.text = text_bright;
    value.palette.text_dim = text_second;
    value.palette.text_muted = text_third;
    value.palette.text_disabled = ui.Color.rgba(110, 114, 134, 170);
    value.palette.icon = text_second;
    value.palette.icon_selected = violet;
    value.palette.icon_disabled = ui.Color.rgba(110, 114, 134, 160);

    // One focal point per view: lavender marks focus, selection and primary
    // work, and the soft fills stay dim enough to sit under body text.
    value.palette.accent = violet;
    value.palette.accent_soft = violet_fill;
    value.palette.accent_hover = ui.Color.rgba(144, 131, 216, 40);
    value.palette.accent_pressed = ui.Color.rgba(144, 131, 216, 70);
    value.palette.accent_border = ui.Color.rgba(144, 131, 216, 160);
    value.palette.accent_border_strong = ui.Color.rgba(209, 205, 253, 235);
    value.palette.violet = violet_hot;
    value.palette.violet_soft = violet_well;

    value.palette.success = sage;
    value.palette.success_soft = ui.Color.rgba(42, 56, 50, 255);
    value.palette.warning = amber;
    value.palette.warning_soft = ui.Color.rgba(58, 50, 40, 255);
    value.palette.danger = rose;
    value.palette.danger_soft = ui.Color.rgba(54, 44, 55, 255);

    // Gently rounded, matching the reference's fields, chips and buttons — still
    // tighter than the zGUI default so the editor keeps its dense feel.
    value.radius_tokens = .{
        .control = 6,
        .card = 8,
        // Square: the scene renders to a rectangular texture, so a rounded
        // frame would clip it and leave black wedges in the corners.
        .viewport = 0,
        .pill = 8,
        .round = 999,
    };
    // Spacing and metrics stay on the editor's dense scale.
    value.space = .{
        .xxs = 2,
        .xs = 3,
        .sm = 5,
        .md = 8,
        .lg = 10,
        .xl = 12,
        .xxl = 16,
    };
    // Every text role runs one step (2px) above the zGUI default.
    value.font = .{
        .tiny = 13,
        .small = 14,
        .body = 15,
        .title = 18,
        .brand = 20,
    };
    value.metrics = .{
        .control_height = 32,
        .compact_control_height = 26,
        .section_header_height = 38,
        .dock_tab_height = 30,
        // The seam between docked panels, measured off the reference at 2px.
        .dock_handle_thickness = 2,
    };
    return value;
}

const std = @import("std");

fn luma(c: ui.Color) u32 {
    return (@as(u32, c.r) * 2 + @as(u32, c.g) * 3 + @as(u32, c.b)) / 6;
}

test "editor theme stays denser than the zGUI default" {
    const value = theme();
    try std.testing.expect(value.radius_tokens.card < ui.theme.fusion_dark.radius_tokens.card);
    try std.testing.expect(value.metrics.control_height < ui.theme.fusion_dark.metrics.control_height);
    try std.testing.expect(value.space.sm < ui.theme.fusion_dark.space.sm);
}

test "violet is the primary accent" {
    const value = theme();
    try std.testing.expectEqual(violet, value.palette.accent);
    try std.testing.expectEqual(violet, value.palette.icon_selected);
    // Accent and its selection fill both read violet: red and blue lead green.
    for ([_]ui.Color{ value.palette.accent, value.palette.accent_soft, value.palette.violet_soft }) |c| {
        try std.testing.expect(c.b > c.g);
        try std.testing.expect(c.r > c.g);
    }
}

test "surfaces sit in the reference's lightness band" {
    const value = theme();
    // The old near-black pass bottomed out around luma 8; panels now land in the
    // high twenties/thirties so the shell reads lifted rather than blacked out.
    try std.testing.expect(luma(value.palette.shell) >= 30);
    try std.testing.expect(luma(value.palette.shell) <= 48);
    try std.testing.expect(luma(value.palette.app) >= 22);
    // Surfaces stay cool: blue leads red on every plate.
    for ([_]ui.Color{
        value.palette.app,      value.palette.shell, value.palette.panel,
        value.palette.panel_soft, value.palette.card,  value.palette.control,
    }) |c| try std.testing.expect(c.b > c.r);
}

test "surface elevation ascends and wells sit below the plates" {
    const value = theme();
    const ramp = [_]ui.Color{
        value.palette.app,        value.palette.shell,
        value.palette.panel,      value.palette.panel_soft,
        value.palette.card,
    };
    for (ramp[1..], 0..) |c, i| try std.testing.expect(luma(c) > luma(ramp[i]));
    // Inputs are cut into the panel rather than raised above it.
    try std.testing.expect(luma(value.palette.control) < luma(value.palette.shell));
    // The scene frame stays the darkest surface of all.
    try std.testing.expect(luma(value.palette.viewport) < luma(value.palette.control));
}

test "corners stay gently rounded" {
    const value = theme();
    const d = ui.theme.fusion_dark.radius_tokens;
    try std.testing.expect(value.radius_tokens.control <= d.control);
    try std.testing.expect(value.radius_tokens.card <= d.card);
    try std.testing.expect(value.radius_tokens.viewport <= d.viewport);
    try std.testing.expect(value.radius_tokens.control >= 4);
}
