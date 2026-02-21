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

    // Backpack
    backpack_model: runtime.AssetHandle = undefined,
    pbr_shader: runtime.Shader = undefined,
    pbr_material: runtime.Material = undefined,
    pbr_material_instance: runtime.MaterialInstance = undefined,
    base_color_tex: runtime.Texture = undefined,
    metal_rough_tex: runtime.Texture = undefined,
    normal_tex: runtime.Texture = undefined,

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

        // --- Backpack ---
        try self.initBackpack(allocator);

        // white point light (upper right)
        _ = try AssetManager.PushLight(allocator, .{
            .kind = .point,
            .position = .{ .x = 1.2, .y = 1.0, .z = 2.0 },
            .ambient = .{ .x = 0.1, .y = 0.1, .z = 0.1 },
            .diffuse = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
            .specular = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        });

        // directional fill light (from above)
        _ = try AssetManager.PushLight(allocator, .{
            .kind = .directional,
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .direction = .{ .x = 0, .y = -1, .z = -0.5 },
            .ambient = .{ .x = 0.05, .y = 0.05, .z = 0.05 },
            .diffuse = .{ .x = 0.6, .y = 0.6, .z = 0.6 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
        });
    }

    fn initBackpack(self: *GameScene, allocator: std.mem.Allocator) !void {
        const gltf_json = @embedFile("assets/meshes/backpack/scene.gltf");
        const bin_data = @embedFile("assets/meshes/backpack/scene.bin");
        const base_color_data = @embedFile("assets/meshes/backpack/Scene_-_Root_baseColor.jpeg");
        const metal_rough_data = @embedFile("assets/meshes/backpack/Scene_-_Root_metallicRoughness.png");
        const normal_data = @embedFile("assets/meshes/backpack/Scene_-_Root_normal.png");

        // Load textures (force RGBA to avoid GL alignment issues)
        self.base_color_tex = try runtime.Texture.fromData(base_color_data, 4);
        self.base_color_tex.generateMipmaps();
        self.base_color_tex.setWrapRepeat();

        self.metal_rough_tex = try runtime.Texture.fromData(metal_rough_data, 4);
        self.metal_rough_tex.generateMipmaps();
        self.metal_rough_tex.setWrapRepeat();

        self.normal_tex = try runtime.Texture.fromData(normal_data, 4);
        self.normal_tex.generateMipmaps();
        self.normal_tex.setWrapRepeat();

        // PBR shader + material
        const pbr_vs = @embedFile("assets/shaders/pbr_vertex.glsl");
        const pbr_fs = @embedFile("assets/shaders/pbr_fragment.glsl");
        self.pbr_shader = try runtime.Shader.init(allocator, pbr_vs, pbr_fs);
        self.pbr_material = runtime.Material.init(allocator, &self.pbr_shader);
        self.pbr_material_instance = self.pbr_material.instaniate(.{
            .ambient = .{ .x = 0.2, .y = 0.2, .z = 0.2 },
            .diffuse = .{ .x = 0.8, .y = 0.8, .z = 0.8 },
            .specular = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .shininess = 64.0,
        });
        self.pbr_material_instance.base_color_texture = &self.base_color_tex;
        self.pbr_material_instance.metallic_roughness_texture = &self.metal_rough_tex;
        self.pbr_material_instance.normal_texture = &self.normal_tex;

        // Parse GLTF and build model
        const gltf = runtime.gltf;
        var result = try gltf.parse(allocator, gltf_json, bin_data);
        const VertexArray = runtime.VertexArray;
        const vao = try VertexArray.init(result.mesh.vertices, result.mesh.indices);
        result.mesh.deinit();

        try vao.setLayout(self.pbr_shader.buffer_layout);

        // Position beside monkey, scale down (node transforms bake in ~100x scale)
        const transform = runtime.Transform{
            .position = .{ .x = 400, .y = 0, .z = 0 },
            .scale = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
        };

        const backpack_model = runtime.Model{
            .vao = vao,
            .material = &self.pbr_material_instance,
            .transform = transform,
        };

        self.backpack_model = try AssetManager.PushModel(allocator, backpack_model);
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
        self.pbr_shader.deinit();
        self.base_color_tex.deinit();
        self.metal_rough_tex.deinit();
        self.normal_tex.deinit();

        allocator.destroy(self);
    }
};
