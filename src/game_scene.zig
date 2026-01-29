const std = @import("std");
const runtime = @import("zephyr_runtime");

const RenderCommand = runtime.RenderCommand;

/// Standalone game scene implementing the Scene interface.
/// Contains all game logic: camera, model, shaders, materials, rendering.
/// Renders to whatever is currently bound (screen or FBO — the scene doesn't know or care).
pub const GameScene = struct {
    allocator: std.mem.Allocator,
    camera: runtime.Camera,
    model: ?runtime.Model = null,
    shader: ?runtime.Shader = null,
    material: ?runtime.Material = null,
    material_instance: ?runtime.MaterialInstance = null,

    pub fn create(allocator: std.mem.Allocator, props: runtime.ApplicationProps) !*GameScene {
        const self = try allocator.create(GameScene);

        const width: f32 = @floatFromInt(props.width);
        const height: f32 = @floatFromInt(props.height);
        const aspect = width / height;

        self.* = GameScene{
            .allocator = allocator,
            .camera = runtime.Camera.new(
                .{ .x = 0, .y = 0, .z = 5 },
                std.math.pi / 4.0,
                aspect,
                0.1,
                100.0,
                true,
            ),
        };

        return self;
    }

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) !void {
        std.log.info("GameScene starting up...", .{});

        const vs_src = @embedFile("assets/shaders/vertex.glsl");
        const fs_src = @embedFile("assets/shaders/fragment.glsl");
        const obj_src = @embedFile("assets/meshes/monkey.obj");

        self.shader = try runtime.Shader.init(allocator, vs_src, fs_src);
        self.material = try runtime.Material.init(allocator, &self.shader.?);
        self.material_instance = self.material.?.instaniate(.{
            .ambient = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .diffuse = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .shininess = 32.0,
        });

        self.model = try runtime.Model.init(allocator, obj_src, &self.material_instance.?, .zero);
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        _ = delta_time;

        RenderCommand.Clear(.{ .x = 0.1, .y = 0.1, .z = 0.15 });

        if (self.model) |*model| {
            const light = runtime.Light{
                .position = .{ .x = 1.2, .y = 1.0, .z = 2.0 },
                .ambient = .{ .x = 0.2, .y = 0.2, .z = 0.2 },
                .diffuse = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
                .specular = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
            };

            if (self.material_instance) |*mat_inst| {
                mat_inst.setUniform("light.position", light.position);
                mat_inst.setUniform("light.ambient", light.ambient);
                mat_inst.setUniform("light.diffuse", light.diffuse);
                mat_inst.setUniform("light.specular", light.specular);
            }

            RenderCommand.Draw(model, &self.camera);
        }
    }

    pub fn onEvent(self: *GameScene, e: runtime.ZEvent) void {
        switch (e) {
            .WindowResize => |resize| {
                const w: f32 = @floatFromInt(resize.width);
                const h: f32 = @floatFromInt(resize.height);
                if (h > 0) {
                    self.camera.setAspectRatio(w / h);
                }
            },
            else => {},
        }
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) void {
        std.log.info("GameScene cleaning up...", .{});

        if (self.shader) |*shader| {
            shader.deinit();
        }
        if (self.material) |*material| {
            material.deinit();
        }

        allocator.destroy(self);
    }
};
