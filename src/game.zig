const editor_camera = @import("editor_camera.zig");
const game_systems = @import("game_systems.zig");
const editor_components = @import("editor_components.zig");
const game_components = @import("game_components.zig");
const zp = @import("zephyr_runtime");

pub const components = &.{
    editor_components.FlyCameraController,
    game_components.KeyboardMovementComponent,
};

/// Game-owned system ordering. The runtime runs this schedule every frame.
pub const update_schedule = zp.Schedule.Spec{
    .update = &.{
        game_systems.keyboardMovementSystem,
        editor_camera.updateActiveSystem,
    },
};
