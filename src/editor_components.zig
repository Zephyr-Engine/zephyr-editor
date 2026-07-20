const scene = @import("zephyr_runtime").scene_schema;

pub const FlyCameraController = struct {
    look_sensitivity: f32 = 0.02,
    pan_sensitivity: f32 = 0.035,
    zoom_speed: f32 = 1.0,
    pitch: f32 = 0,
    yaw: f32 = 0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e02",
        .name = "zephyr.game.FlyCameraController",
        .display_name = "Fly Camera Controller",
        .version = 1,
        .fields = &.{
            .{ .name = "look_sensitivity", .number = 1, .display_name = "Look Sensitivity", .editor = .{ .min = 0 } },
            .{ .name = "pan_sensitivity", .number = 2, .display_name = "Pan Sensitivity", .editor = .{ .min = 0 } },
            .{ .name = "zoom_speed", .number = 3, .display_name = "Zoom Speed", .editor = .{ .min = 0 } },
            .{ .name = "pitch", .number = 4 },
            .{ .name = "yaw", .number = 5 },
        },
    };
};
