const std = @import("std");
const zp = @import("zephyr_runtime");
const editor_camera = @import("editor_camera.zig");

const Material = zp.Material;
const AssetId = zp.AssetId;
const Vec3 = zp.Vec3;
const Mesh = zp.Mesh;

pub const GameScene = struct {
    mesh: AssetId,
    material: AssetId,
    monkey: zp.ecs.EntityID,
    camera_entity: zp.ecs.EntityID,

    pub fn onStartup(self: *GameScene, ctx: *zp.RuntimeContext) !void {
        std.log.info("Starting up game scene", .{});

        self.mesh = try ctx.assets.register(Mesh, "monkey.zmesh");
        self.material = try ctx.assets.register(Material, "monkey.zamat");

        self.monkey = try ctx.world.spawnWith(.{
            zp.components.TransformComponent{},
            zp.components.MeshRenderComponent{
                .mesh = self.mesh,
                .material = self.material,
            },
        });

        self.camera_entity = try ctx.world.spawnWith(.{
            zp.components.TransformComponent{
                .position = Vec3.new(0, 0, 3),
            },
            zp.components.CameraComponent{},
            zp.components.FlyCameraController{},
        });
        try zp.setActiveCamera(&ctx.world, self.camera_entity);
    }

    pub fn onUpdate(_: *GameScene, ctx: *zp.RuntimeContext, delta_time: f32) !void {
        _ = delta_time;
        editor_camera.updateActive(&ctx.world);
    }

    pub fn onEvent(_: *GameScene, _: *zp.RuntimeContext, _: zp.ZEvent) !void {}

    pub fn onCleanup(self: *GameScene, ctx: *zp.RuntimeContext) !void {
        std.log.info("Game Scene Cleaning up...", .{});
        ctx.world.despawn(self.monkey);
        ctx.world.despawn(self.camera_entity);
    }
};
