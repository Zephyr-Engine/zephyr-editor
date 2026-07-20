const scene = @import("zephyr_runtime").scene_schema;

pub const KeyboardMovementComponent = struct {
    speed: f32 = 2.5,
    sprint_multiplier: f32 = 2.0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e01",
        .name = "zephyr.game.KeyboardMovement",
        .display_name = "Keyboard Movement",
        .version = 1,
        .fields = &.{
            .{ .name = "speed", .number = 1, .display_name = "Speed", .editor = .{ .min = 0 } },
            .{ .name = "sprint_multiplier", .number = 2, .display_name = "Sprint Multiplier", .editor = .{ .min = 1 } },
        },
    };
};
