/// Editor-only camera navigation state. Games opt into it by registering this
/// component; Zephyr Runtime does not require or own this behaviour.
pub const FlyCameraController = struct {
    look_sensitivity: f32 = 0.02,
    pan_sensitivity: f32 = 0.035,
    zoom_speed: f32 = 1.0,
    pitch: f32 = 0,
    yaw: f32 = 0,
};
