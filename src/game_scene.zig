const std = @import("std");
const zp = @import("zephyr_runtime");

const VertexArray = zp.VertexArray;
const Shader = zp.Shader;
const Input = zp.Input;
const Vec2 = zp.Vec2;
const gl = zp.gl;

const vertices = [_]f32{
    0.5, 0.5, 0.0, // top right
    0.5, -0.5, 0.0, // bottom right
    -0.5, -0.5, 0.0, // bottom left
    -0.5, 0.5, 0.0, // top left
};

const indices = [_]u32{
    0, 1, 3, // first triangle
    1, 2, 3, // second triangle
};

const vs_src: [*c]const u8 = @embedFile("assets/shaders/vertex.glsl");
const fs_src: [*c]const u8 = @embedFile("assets/shaders/fragment.glsl");

const speed: f32 = 2.0;

pub const GameScene = struct {
    allocator: std.mem.Allocator,
    shader: Shader,
    vao: VertexArray,
    offset: Vec2,

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) !void {
        std.log.info("Starting up game scene", .{});

        self.offset = .{
            .x = 0,
            .y = 0,
        };
        self.allocator = allocator;
        self.vao = VertexArray.init(&vertices, &indices) catch |err| {
            std.log.err("Error creating vertex array: {}", .{err});
            return;
        };
        self.shader = Shader.init(allocator, vs_src, fs_src) catch |err| {
            std.log.err("Error creating shader: {}", .{err});
            return;
        };

        self.vao.setLayout();
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) !void {
        if (Input.IsKeyHeld(.A)) {
            self.offset.x -= speed * delta_time;
        }
        if (Input.IsKeyHeld(.D)) {
            self.offset.x += speed * delta_time;
        }
        if (Input.IsKeyHeld(.W)) {
            self.offset.y += speed * delta_time;
        }
        if (Input.IsKeyHeld(.S)) {
            self.offset.y -= speed * delta_time;
        }

        gl.glClearColor(0.4, 0.4, 0.4, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        self.shader.setUniform("u_offset", self.offset);
        self.vao.draw();
    }

    pub fn onEvent(self: *GameScene, e: zp.ZEvent) !void {
        _ = self;
        _ = e;
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) !void {
        _ = allocator;
        std.log.info("Game Scene Cleaning up...", .{});
        self.shader.deinit();
    }
};
