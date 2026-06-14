const std = @import("std");
const zp = @import("zephyr_runtime");

const EditorCamera = zp.EditorCamera;
const Material = zp.Material;
const AssetId = zp.AssetId;
const Vec3 = zp.Vec3;
const Mesh = zp.Mesh;
const gl = zp.gl;

pub const GameScene = struct {
    mesh: AssetId,
    material: AssetId,
    editor_camera: EditorCamera,

    pub fn onStartup(self: *GameScene, ctx: *zp.RuntimeContext) !void {
        std.log.info("Starting up game scene", .{});

        self.editor_camera = EditorCamera.init(
            Vec3.new(0, 0, 3),
            16.0 / 9.0,
        );

        self.mesh = try ctx.assets.register(Mesh, "monkey.zmesh");
        self.material = try ctx.assets.register(Material, "monkey.zamat");

        gl.glEnable(gl.GL_DEPTH_TEST);
    }

    pub fn onUpdate(self: *GameScene, ctx: *zp.RuntimeContext, delta_time: f32) !void {
        _ = delta_time;
        self.editor_camera.camera.aspect = ctx.render_viewport.aspect();
        self.editor_camera.update();

        gl.glEnable(gl.GL_DEPTH_TEST);
        gl.glClearColor(0.4, 0.4, 0.4, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        const material = ctx.assets.get(Material, self.material) orelse return;
        const mesh = ctx.assets.get(Mesh, self.mesh) orelse return;

        material.bind();
        material.setUniform("u_view", self.editor_camera.camera.viewMatrix());
        material.setUniform("u_projection", self.editor_camera.camera.projectionMatrix());
        mesh.draw();
    }

    pub fn onEvent(self: *GameScene, _: *zp.RuntimeContext, e: zp.ZEvent) !void {
        self.editor_camera.processEvent(e);
    }

    pub fn onCleanup(_: *GameScene, _: *zp.RuntimeContext) !void {
        std.log.info("Game Scene Cleaning up...", .{});
    }
};
