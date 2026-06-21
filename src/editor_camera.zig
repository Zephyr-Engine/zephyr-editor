const std = @import("std");
const zp = @import("zephyr_runtime");

pub const max_pitch: f32 = std.math.pi / 2.0 - 0.02;

pub fn updateActive(world: *zp.ecs.World) void {
    const entity = zp.activeCamera(world) orelse return;
    const transform = world.getComponent(entity, zp.components.TransformComponent) orelse return;
    const controller = world.getComponent(entity, zp.components.FlyCameraController) orelse return;
    update(transform, controller);
}

pub fn update(
    transform: *zp.components.TransformComponent,
    controller: *zp.components.FlyCameraController,
) void {
    const delta = zp.Input.GetMouseMoveDelta();

    if (zp.Input.IsButtonHeld(.Right)) {
        controller.yaw -= delta.x * controller.look_sensitivity;
        controller.pitch -= delta.y * controller.look_sensitivity;
        controller.pitch = std.math.clamp(controller.pitch, -max_pitch, max_pitch);
        transform.rotation = orientation(controller.yaw, controller.pitch);
    }

    if (zp.Input.IsButtonHeld(.Left)) {
        transform.position = transform.position.sub(
            transform.right().scale(delta.x * controller.pan_sensitivity),
        );
        transform.position = transform.position.sub(
            transform.up().scale(delta.y * controller.pan_sensitivity),
        );
    }

    const scroll = zp.Input.GetMouseMoveScroll();
    if (scroll.y != 0) {
        transform.position = transform.position.add(
            transform.forward().scale(scroll.y * controller.zoom_speed),
        );
    }
}

fn orientation(yaw: f32, pitch: f32) zp.Quat {
    const yaw_rotation = zp.Quat.fromAxisAngle(zp.Vec3.new(0, 1, 0), yaw);
    const pitch_rotation = zp.Quat.fromAxisAngle(zp.Vec3.new(1, 0, 0), pitch);
    return yaw_rotation.mul(pitch_rotation);
}

test "editor camera orientation uses controller yaw and pitch" {
    const rotation = orientation(std.math.pi / 2.0, 0);
    const forward = rotation.rotateVec3(zp.Vec3.new(0, 0, -1));

    try std.testing.expectApproxEqAbs(@as(f32, -1), forward.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), forward.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), forward.z, 0.0001);
}
