const std = @import("std");
const zp = @import("zephyr_runtime");
const Input = zp.Input;
const gl = zp.gl;

pub const std_options = zp.recommended_std_options;

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

pub fn main() void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app = zp.Application.init(allocator, .{
        .title = "Zephyr Engine",
        .width = null,
        .height = null,
    }) catch |err| {
        std.log.err("Application init failed: {}", .{err});
        return;
    };
    defer app.deinit();

    const vao = zp.VertexArray.init(&vertices, &indices);
    const shader = zp.Shader.init(vs_src, fs_src) catch |err| {
        std.log.err("Error creating shader: {}\n", .{err});
        return;
    };

    vao.bind();
    zp.gl.glVertexAttribPointer(0, 3, zp.gl.GL_FLOAT, zp.gl.GL_FALSE, 3 * @sizeOf(f32), @ptrFromInt(0));
    zp.gl.glEnableVertexAttribArray(0);

    const offset_loc = zp.gl.glGetUniformLocation(shader.id, "u_offset");
    var offset_x: f32 = 0.0;
    var offset_y: f32 = 0.0;
    const speed: f32 = 2.0;

    while (app.window.shouldCloseWindow()) {
        zp.Window.HandleInput();
        const current_time = zp.Window.GetTime();
        app.time.update(@floatCast(current_time));

        if (Input.IsKeyHeld(.A)) {
            offset_x -= speed * app.time.delta_time;
        }
        if (Input.IsKeyHeld(.D)) {
            offset_x += speed * app.time.delta_time;
        }
        if (Input.IsKeyHeld(.W)) {
            offset_y += speed * app.time.delta_time;
        }
        if (Input.IsKeyHeld(.S)) {
            offset_y -= speed * app.time.delta_time;
        }

        gl.glClearColor(0.4, 0.4, 0.4, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        shader.bind();
        gl.glUniform2f(offset_loc, offset_x, offset_y);
        vao.bind();
        gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));

        app.window.swapBuffers();
        Input.Clear();
    }

    zp.Window.HandleInput();
}
