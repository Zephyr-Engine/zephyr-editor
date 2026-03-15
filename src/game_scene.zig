const std = @import("std");
const zp = @import("zephyr_runtime");

const VertexArray = zp.VertexArray;
const Shader = zp.Shader;
const Input = zp.Input;
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
    offset_x: f32,
    offset_y: f32,

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) void {
        std.log.info("Starting up game scene", .{});

        self.offset_x = 0;
        self.offset_y = 0;
        self.allocator = allocator;
        self.vao = VertexArray.init(&vertices, &indices);
        self.shader = Shader.init(vs_src, fs_src) catch |err| {
            std.log.err("Error creating shader: {}\n", .{err});
            return;
        };

        self.vao.bind();
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, zp.gl.GL_FALSE, 3 * @sizeOf(f32), @ptrFromInt(0));
        gl.glEnableVertexAttribArray(0);
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        const offset_loc = zp.gl.glGetUniformLocation(self.shader.id, "u_offset");

        if (Input.IsKeyHeld(.A)) {
            self.offset_x -= speed * delta_time;
        }
        if (Input.IsKeyHeld(.D)) {
            self.offset_x += speed * delta_time;
        }
        if (Input.IsKeyHeld(.W)) {
            self.offset_y += speed * delta_time;
        }
        if (Input.IsKeyHeld(.S)) {
            self.offset_y -= speed * delta_time;
        }

        gl.glClearColor(0.4, 0.4, 0.4, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        self.shader.bind();
        gl.glUniform2f(offset_loc, self.offset_x, self.offset_y);
        self.vao.bind();
        gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));
    }

    pub fn onEvent(self: *GameScene, e: zp.ZEvent) void {
        _ = self;
        _ = e;
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        std.log.info("Game Scene Cleaning up...", .{});
    }
};
