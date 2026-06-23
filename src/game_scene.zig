const std = @import("std");

const editor_components = @import("editor_components.zig");
const game_components = @import("game_components.zig");
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

    pub fn onUpdate(_: *GameScene, _: *zp.RuntimeContext(Game.Ecs), _: f32) !void {}

    pub fn onEvent(_: *GameScene, _: *zp.RuntimeContext(Game.Ecs), _: zp.ZEvent) !void {}

    pub fn onCleanup(self: *GameScene, ctx: *zp.RuntimeContext(Game.Ecs)) !void {
        std.log.info("Game Scene Cleaning up...", .{});
        ctx.world.despawn(self.monkey);
        ctx.world.despawn(self.camera_entity);
    }
};
