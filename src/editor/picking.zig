const std = @import("std");
const runtime = @import("zephyr_runtime");

const Framebuffer = runtime.Framebuffer;
const Shader = runtime.Shader;
const Camera = runtime.Camera;
const RenderCommand = runtime.RenderCommand;
const AssetManager = runtime.AssetManager;
const AssetHandle = runtime.AssetHandle;

const utility_vertex_src =
    \\#version 330 core
    \\layout(location = 0) in vec3 aPos;
    \\layout(location = 1) in vec3 aNormal;
    \\layout(location = 2) in vec2 aTexCoord;
    \\uniform mat4 u_mvp;
    \\void main() { gl_Position = u_mvp * vec4(aPos, 1.0); }
    \\
;

const picking_fragment_src =
    \\#version 330 core
    \\uniform int u_objectId;
    \\out vec4 FragColor;
    \\void main() {
    \\    int id = u_objectId + 1;
    \\    FragColor = vec4(float(id & 0xFF)/255.0, float((id>>8)&0xFF)/255.0, float((id>>16)&0xFF)/255.0, 1.0);
    \\}
    \\
;

pub const PickingSystem = struct {
    framebuffer: Framebuffer,
    shader: Shader,

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !PickingSystem {
        var framebuffer = try Framebuffer.init(width, height);
        errdefer framebuffer.deinit();

        const shader = Shader.init(allocator, utility_vertex_src, picking_fragment_src) catch |err| {
            std.log.err("Failed to create picking shader: {}", .{err});
            return error.OutOfMemory;
        };

        return .{
            .framebuffer = framebuffer,
            .shader = shader,
        };
    }

    pub fn deinit(self: *PickingSystem) void {
        self.framebuffer.deinit();
        self.shader.deinit();
    }

    pub fn resize(self: *PickingSystem, width: i32, height: i32) !void {
        try self.framebuffer.resize(width, height);
    }

    pub fn pick(self: *PickingSystem, camera: *Camera, x: i32, y: i32) ?AssetHandle {
        self.framebuffer.bind();
        RenderCommand.Clear(.{ .x = 0, .y = 0, .z = 0 });

        self.shader.bind();
        const vp = camera.viewProjectionMatrix();

        for (AssetManager.GetModels(), 0..) |model, i| {
            const model_mat = AssetManager.GetWorldMatrix(i);
            const mvp = model_mat.mul(vp);
            self.shader.setUniform("u_mvp", mvp);
            self.shader.setUniform("u_objectId", @as(i32, @intCast(i)));
            model.vao.draw();
        }

        const pixel = self.framebuffer.readPixel(x, y);
        Framebuffer.unbind();

        const id: u32 = @as(u32, pixel[0]) | (@as(u32, pixel[1]) << 8) | (@as(u32, pixel[2]) << 16);
        if (id == 0) {
            return null;
        }
        return @intCast(id - 1);
    }
};
