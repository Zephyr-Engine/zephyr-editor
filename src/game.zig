const editor_components = @import("editor_components.zig");
const game_components = @import("game_components.zig");
const zp = @import("zephyr_runtime");

pub const Ecs = zp.GameEcs(&.{
    editor_components.FlyCameraController,
    game_components.KeyboardMovementComponent,
});
