const editor_camera = @import("editor_camera.zig");
const game_systems = @import("game_systems.zig");
const game_types = @import("game_types.zig");

pub const Ecs = game_types.Ecs;

/// Game-owned system ordering. The runtime runs this schedule every frame.
pub const update_schedule = Ecs.Schedule.Spec{
    .update = &.{
        game_systems.keyboardMovementSystem,
        editor_camera.updateActiveSystem,
    },
};
