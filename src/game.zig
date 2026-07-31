const editor_camera = @import("editor_camera.zig");
const game_systems = @import("game_systems.zig");
const editor_components = @import("editor_components.zig");
const game_components = @import("game_components.zig");
const zp = @import("zephyr_runtime");

/// Editor-owned components and system ordering run by the runtime each frame.
pub const definition = zp.Game{
    .components = &.{
        editor_components.FlyCameraController,
        game_components.KeyboardMovementComponent,
    },
    .update_schedule = .{
        .update = &.{
            game_systems.keyboardMovementSystem,
            editor_camera.updateActiveSystem,
        },
    },
};
