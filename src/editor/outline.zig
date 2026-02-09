const std = @import("std");
const runtime = @import("zephyr_runtime");

const Shader = runtime.Shader;
const Camera = runtime.Camera;
const RenderCommand = runtime.RenderCommand;
const Vec3 = runtime.Vec3;

const utility_vertex_src =
    \\#version 330 core
    \\layout(location = 0) in vec3 aPos;
    \\layout(location = 1) in vec3 aNormal;
    \\layout(location = 2) in vec2 aTexCoord;
    \\uniform mat4 u_mvp;
    \\void main() { gl_Position = u_mvp * vec4(aPos, 1.0); }
    \\
;

const outline_fragment_src =
    \\#version 330 core
    \\uniform vec3 u_outlineColor;
    \\out vec4 FragColor;
    \\void main() { FragColor = vec4(u_outlineColor, 1.0); }
    \\
;

pub const OutlineRenderer = struct {
    shader: Shader,

    pub fn init(allocator: std.mem.Allocator) !OutlineRenderer {
        const shader = Shader.init(allocator, utility_vertex_src, outline_fragment_src) catch |err| {
            std.log.err("Failed to create outline shader: {}", .{err});
            return error.OutOfMemory;
        };

        return .{
            .shader = shader,
        };
    }

    pub fn deinit(self: *OutlineRenderer) void {
        self.shader.deinit();
    }

    pub fn draw(self: *OutlineRenderer, camera: *Camera, model_index: usize, color: Vec3, scale: f32) void {
        self.shader.bind();
        self.shader.setUniform("u_outlineColor", color);
        RenderCommand.DrawStencilOutline(camera, model_index, &self.shader, scale);
    }
};
