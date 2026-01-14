const std = @import("std");
const runtime = @import("zephyr_runtime");
const Input = runtime.Input;

pub const std_options = runtime.recommended_std_options;

const movement_speed = 0.2;

const GameScene = struct {
    vao: runtime.VertexArray,
    shader: runtime.Shader,
    material: runtime.Material,
    transparency: f32,
    camera: runtime.Camera,

    pub fn create(allocator: std.mem.Allocator, props: runtime.ApplicationProps) !*GameScene {
        const self = try allocator.create(GameScene);
        const aspect = @as(f32, @floatFromInt(props.width)) / @as(f32, @floatFromInt(props.height));
        const camera = runtime.Camera.new(
            .{ .x = 0, .y = 0, .z = 5 },
            std.math.pi / 4.0,
            aspect, // aspect ratio from window dimensions
            0.1, // near plane
            100.0, // far plane
            true, // is_active
        );

        self.* = GameScene{
            .vao = undefined,
            .shader = undefined,
            .material = undefined,
            .transparency = 0.0,
            .camera = camera,
        };
        return self;
    }

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) !void {
        std.log.info("GameScene starting up...", .{});

        const vertices = [_]f32{
            // Front face (z = 0.5)
            -0.5, -0.5, 0.5, // 0: bottom left
            0.5, -0.5, 0.5, // 1: bottom right
            0.5, 0.5, 0.5, // 2: top right
            -0.5, 0.5, 0.5, // 3: top left
            // Back face (z = -0.5)
            -0.5, -0.5, -0.5, // 4: bottom left
            0.5, -0.5, -0.5, // 5: bottom right
            0.5, 0.5, -0.5, // 6: top right
            -0.5, 0.5, -0.5, // 7: top left
        };

        const indices = [_]u32{
            // Front face
            0, 1, 2,
            2, 3, 0,
            // Back face
            5, 4, 7,
            7, 6, 5,
            // Left face
            4, 0, 3,
            3, 7, 4,
            // Right face
            1, 5, 6,
            6, 2, 1,
            // Top face
            3, 2, 6,
            6, 7, 3,
            // Bottom face
            4, 5, 1,
            1, 0, 4,
        };

        self.vao = runtime.VertexArray.init(&vertices, &indices);

        const vs_src = @embedFile("shaders/vertex.glsl");
        const fs_src = @embedFile("shaders/fragment.glsl");
        self.shader = try runtime.Shader.init(allocator, vs_src, fs_src);
        self.material = try runtime.Material.init(allocator, &self.shader);

        self.vao.setLayout(self.shader.buffer_layout);
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        runtime.RenderCommand.Clear(.{ .x = 0.4, .y = 0.4, .z = 0.4 });
        const speed = movement_speed * delta_time;

        if (Input.isKeyPressed(.Escape)) {
            std.log.info("Escape key pressed, exiting...", .{});
        } else if (Input.isKeyHeld(.Space)) {
            std.log.info("Space key pressed!", .{});
        } else if (Input.isKeyHeld(.A)) {
            self.transparency += speed;
            if (self.transparency > 1.0) {
                self.transparency = 1.0;
            }
            // self.position.x -= speed;
        } else if (Input.isKeyHeld(.D)) {
            self.transparency -= speed;
            if (self.transparency < 0.0) {
                self.transparency = 0.0;
            }
            // self.position.x += speed;
        }
        // else if (Input.isKeyHeld(.W)) {
        //     self.position.y += speed;
        // } else if (Input.isKeyHeld(.S)) {
        //     self.position.y -= speed;
        // }

        if (Input.isButtonHeld(.Left)) {
            self.camera.pan(Input.mouse_delta.x, Input.mouse_delta.y, speed * 10);
        } else if (Input.isButtonHeld(.Right)) {
            self.camera.fpsLook(Input.mouse_delta.x, Input.mouse_delta.y, speed * 10);
        }

        if (Input.isScrollingY()) {
            self.camera.zoom(Input.mouse_scroll_delta.y, speed);
        }

        self.material.setUniform("r_color", self.transparency);
        self.material.setUniform("r_position", self.camera.viewProjectionMatrix());

        runtime.RenderCommand.Draw(self.vao);
    }

    pub fn onEvent(self: *GameScene, e: runtime.ZEvent) void {
        switch (e) {
            .KeyPressed => |key| {
                std.log.info("GameScene received key: {s}", .{@tagName(key)});
                if (key == .Escape) {
                    runtime.Application.Shutdown();
                }
            },
            .WindowClose => {
                std.log.info("GameScene shutting down...", .{});
            },
            .WindowResize => |resize| {
                const aspect = @as(f32, @floatFromInt(resize.width)) /
                    @as(f32, @floatFromInt(resize.height));
                self.camera.setAspectRatio(aspect);
            },
            else => {},
        }
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) void {
        std.log.info("GameScene cleaning up...", .{});
        self.shader.deinit(allocator);
        self.material.deinit();
        allocator.destroy(self);
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application = try runtime.Application.init(allocator, .{
        .width = null,
        .height = null,
        .title = "Zephyr Game",
    });
    defer application.deinit(allocator);

    // application.window.setWireframeMode();

    const app_props = application.getProps();
    const game_scene = try GameScene.create(allocator, app_props);
    const scene = runtime.Scene.init(game_scene);
    try application.pushScene(scene);

    application.run();
}
