const std = @import("std");

const game_components = @import("game_components.zig");
const editor_camera = @import("editor_camera.zig");
const editor_components = @import("editor_components.zig");
const zp = @import("zephyr_runtime");
const Game = @import("game.zig");

const KeyboardMovementComponent = game_components.KeyboardMovementComponent;
const TransformComponent = zp.components.TransformComponent;
const Material = zp.Material;
const AssetId = zp.AssetId;
const Vec3 = zp.Vec3;
const Mesh = zp.Mesh;

pub const GameScene = struct {
    mesh: AssetId,
    material: AssetId,
    monkey: zp.ecs.EntityID,
    camera_entity: zp.ecs.EntityID,

    pub fn onStartup(self: *GameScene, ctx: *zp.RuntimeContext(Game.Ecs)) !void {
        std.log.info("Starting up game scene", .{});
        std.log.info("Monkey controls: WASD or arrow keys; hold Left Shift to sprint", .{});

        self.mesh = try ctx.assets.register(Mesh, "monkey.zmesh");
        self.material = try ctx.assets.register(Material, "monkey.zamat");

        self.monkey = try ctx.world.spawnWith(.{
            TransformComponent{},
            zp.components.MeshRenderComponent{
                .mesh = self.mesh,
                .material = self.material,
            },
            KeyboardMovementComponent{},
        });

        self.camera_entity = try ctx.world.spawnWith(.{
            zp.components.TransformComponent{
                .position = Vec3.new(0, 0, 3),
            },
            zp.components.CameraComponent{},
            editor_components.FlyCameraController{},
        });
        try zp.setActiveCamera(&ctx.world, self.camera_entity);
    }

    pub fn onUpdate(_: *GameScene, ctx: *zp.RuntimeContext(Game.Ecs), delta_time: f32) !void {
        const input = ctx.world.getResource(zp.Input);
        keyboardMovementSystem(&ctx.world, input, delta_time);
        editor_camera.updateActive(&ctx.world, input);
    }

    pub fn onEvent(_: *GameScene, _: *zp.RuntimeContext(Game.Ecs), _: zp.ZEvent) !void {}

    pub fn onCleanup(self: *GameScene, ctx: *zp.RuntimeContext(Game.Ecs)) !void {
        std.log.info("Game Scene Cleaning up...", .{});
        ctx.world.despawn(self.monkey);
        ctx.world.despawn(self.camera_entity);
    }
};

/// Moves every keyboard-controlled entity. This is deliberately an ECS system:
/// it queries behaviour and transform components rather than targeting the
/// scene's `monkey` entity directly.
fn keyboardMovementSystem(world: *Game.Ecs.World, input: *const zp.Input, delta_time: f32) void {
    const direction = keyboardDirection(input);
    if (direction.x == 0 and direction.z == 0) return;

    var iter = world.query(.{
        .write = &.{TransformComponent},
        .read = &.{KeyboardMovementComponent},
    });

    while (iter.each()) |entity| {
        const transform = entity.write(TransformComponent);
        const controller = entity.read(KeyboardMovementComponent);

        const speed = controller.speed * if (input.isKeyHeld(.LeftShift))
            controller.sprint_multiplier
        else
            1.0;
        const movement = direction.normalize().scale(speed * delta_time);
        transform.position = transform.position.add(movement);
        transform.rotation = zp.Quat.fromAxisAngle(
            Vec3.new(0, 1, 0),
            std.math.atan2(-movement.x, -movement.z),
        );
    }
}

fn keyboardDirection(input: *const zp.Input) Vec3 {
    var direction = Vec3.zero;

    if (input.isKeyHeld(.W) or input.isKeyHeld(.Up)) direction.z -= 1;
    if (input.isKeyHeld(.S) or input.isKeyHeld(.Down)) direction.z += 1;
    if (input.isKeyHeld(.A) or input.isKeyHeld(.Left)) direction.x -= 1;
    if (input.isKeyHeld(.D) or input.isKeyHeld(.Right)) direction.x += 1;

    return direction;
}
