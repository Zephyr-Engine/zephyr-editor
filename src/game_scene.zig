const std = @import("std");
const runtime = @import("zephyr_runtime");

const Input = runtime.Input;
const AssetHandle = runtime.AssetHandle;
const AssetManager = runtime.AssetManager;
const RenderCommand = runtime.RenderCommand;

const movement_speed = 0.6;

pub const GameScene = struct {
    allocator: std.mem.Allocator,
    camera: runtime.Camera,
    model: runtime.AssetHandle = undefined,
    shader: runtime.Shader = undefined,
    material: runtime.Material = undefined,
    material_instance: runtime.MaterialInstance = undefined,

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
        self.material = runtime.Material.init(allocator, &self.shader);
        self.material_instance = self.material.instaniate(.{
            .ambient = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .diffuse = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .shininess = 32.0,
        });

        const model = try runtime.Model.init(allocator, obj_src, &self.material_instance, runtime.Transform.default);
        self.model = AssetManager.PushModel(allocator, model) catch |err| {
            std.log.err("Failed to push model: {}", .{err});
            return;
        };
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        const speed = movement_speed * delta_time;

        RenderCommand.Clear(.{ .x = 0.1, .y = 0.1, .z = 0.15 });

        var model = AssetManager.GetModel(self.model);
        if (Input.IsKeyHeld(.A)) {
            model.transform.translate(.{ .x = -speed, .y = 0, .z = 0 });
        } else if (Input.IsKeyHeld(.D)) {
            model.transform.translate(.{ .x = speed, .y = 0, .z = 0 });
        } else if (Input.IsKeyHeld(.W)) {
            model.transform.translate(.{ .x = 0, .y = 0, .z = -speed });
        } else if (Input.IsKeyHeld(.S)) {
            model.transform.translate(.{ .x = 0, .y = 0, .z = speed });
        }

        const light = runtime.Light{
            .position = .{ .x = 1.2, .y = 1.0, .z = 2.0 },
            .ambient = .{ .x = 0.2, .y = 0.2, .z = 0.2 },
            .diffuse = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .specular = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        };

        self.material_instance.setUniform("light.position", light.position);
        self.material_instance.setUniform("light.ambient", light.ambient);
        self.material_instance.setUniform("light.diffuse", light.diffuse);
        self.material_instance.setUniform("light.specular", light.specular);

        RenderCommand.Draw(&self.camera);
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

        self.shader.deinit();

        allocator.destroy(self);
    }
};
