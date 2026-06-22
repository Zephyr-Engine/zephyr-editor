const zp = @import("zephyr_runtime");
const editor_components = @import("editor_components.zig");
const game_components = @import("game_components.zig");

/// The editor sample owns this registry. Add gameplay components here without
/// changing Zephyr Runtime source code.
pub const Ecs = zp.GameEcs(&.{
    editor_components.FlyCameraController,
    game_components.KeyboardMovementComponent,
});
