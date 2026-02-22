const std = @import("std");
const runtime = @import("zephyr_runtime");

const Input = runtime.Input;
const AssetHandle = runtime.AssetHandle;
const AssetManager = runtime.AssetManager;

const movement_speed = 0.6;

const plane_obj =
    \\# Ground plane
    \\v -1.0  0.0 -1.0
    \\v  1.0  0.0 -1.0
    \\v  1.0  0.0  1.0
    \\v -1.0  0.0  1.0
    \\vn 0.0 1.0 0.0
    \\f 1//1 2//1 3//1
    \\f 1//1 3//1 4//1
    \\
;

pub const GameScene = struct {
    allocator: std.mem.Allocator,
    model: runtime.AssetHandle = undefined,
    backpack_model: runtime.AssetHandle = undefined,

    pub fn create(allocator: std.mem.Allocator, props: runtime.ApplicationProps) !*GameScene {
        _ = props;
        const self = try allocator.create(GameScene);

        self.* = GameScene{
            .allocator = allocator,
        };

        return self;
    }

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) !void {
        std.log.info("GameScene starting up...", .{});

        const vs_src = @embedFile("assets/shaders/vertex.glsl");
        const fs_src = @embedFile("assets/shaders/fragment.glsl");

        const shader = try AssetManager.LoadShader(allocator, vs_src, fs_src);
        const mat = try AssetManager.LoadMaterial(allocator, shader);
        const mat_inst = try AssetManager.LoadMaterialInstance(allocator, mat, .{
            .ambient = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .diffuse = .{ .x = 1.0, .y = 0.5, .z = 0.31 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .shininess = 32.0,
        });

        self.model = try AssetManager.LoadModel(allocator, .{
            .obj = @embedFile("assets/meshes/monkey.obj"),
            .instance = mat_inst,
        });

        _ = try AssetManager.LoadGltfPbr(allocator, .{
            .gltf_json = @embedFile("assets/meshes/backpack/scene.gltf"),
            .bin_data = @embedFile("assets/meshes/backpack/scene.bin"),
            .base_color = @embedFile("assets/meshes/backpack/Scene_-_Root_baseColor.jpeg"),
            .metallic_roughness = @embedFile("assets/meshes/backpack/Scene_-_Root_metallicRoughness.png"),
            .normal = @embedFile("assets/meshes/backpack/Scene_-_Root_normal.png"),
            .transform = .{
                .position = .{ .x = 400, .y = 100, .z = 0 },
                .scale = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        });

        _ = try AssetManager.PushLight(allocator, .{
            .kind = .point,
            .position = .{ .x = 1.2, .y = 1.0, .z = 2.0 },
            .ambient = .{ .x = 0.1, .y = 0.1, .z = 0.1 },
            .diffuse = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
            .specular = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        });

        _ = try AssetManager.PushLight(allocator, .{
            .kind = .directional,
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .direction = .{ .x = 0, .y = -1, .z = -0.5 },
            .ambient = .{ .x = 0.05, .y = 0.05, .z = 0.05 },
            .diffuse = .{ .x = 0.6, .y = 0.6, .z = 0.6 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
        });

        // Ground plane — light beige so shadows are easy to see
        const ground_mat = try AssetManager.LoadMaterialInstance(allocator, mat, .{
            .ambient = .{ .x = 0.8, .y = 0.75, .z = 0.65 },
            .diffuse = .{ .x = 0.8, .y = 0.75, .z = 0.65 },
            .specular = .{ .x = 0.2, .y = 0.2, .z = 0.2 },
            .shininess = 8.0,
        });
        _ = try AssetManager.LoadModel(allocator, .{
            .obj = plane_obj,
            .instance = ground_mat,
            .transform = .{
                .position = .{ .x = 0, .y = -1.5, .z = 0 },
                .scale = .{ .x = 15, .y = 1, .z = 15 },
            },
        });
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        const speed = movement_speed * delta_time;

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
    }

    pub fn onEvent(_: *GameScene, e: runtime.ZEvent) void {
        switch (e) {
            .WindowResize => |resize| {
                const w: f32 = @floatFromInt(resize.width);
                const h: f32 = @floatFromInt(resize.height);
                if (h > 0) {
                    if (AssetManager.GetActiveCamera()) |camera| {
                        camera.setAspectRatio(w / h);
                    }
                }
            },
            else => {},
        }
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) void {
        std.log.info("GameScene cleaning up...", .{});
        allocator.destroy(self);
    }
};
