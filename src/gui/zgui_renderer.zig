const std = @import("std");
const runtime = @import("zephyr_runtime");
const zgui = @import("zgui");

const c = runtime.c;
const gl = c.glad;
const GuiContext = zgui.GuiContext;
const Renderer = zgui.Renderer;
const TextureHandle = zgui.TextureHandle;
const TextureFormat = zgui.TextureFormat;
const Vertex = zgui.Vertex;

/// OpenGL renderer for zGUI that uses zephyr-runtime's GL bindings
pub const ZephyrGuiRenderer = struct {
    shader: u32,
    vbo: u32,
    ibo: u32,
    vao: u32,
    proj_loc: i32,
    tex_loc: i32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ZephyrGuiRenderer {
        var self = ZephyrGuiRenderer{
            .shader = 0,
            .vbo = 0,
            .ibo = 0,
            .vao = 0,
            .proj_loc = 0,
            .tex_loc = 0,
            .allocator = allocator,
        };

        self.shader = createShader();
        setupBuffers(&self);

        // Set up OpenGL state for GUI rendering
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);

        return self;
    }

    pub fn deinit(self: *ZephyrGuiRenderer) void {
        gl.glDeleteProgram(self.shader);
        gl.glDeleteBuffers(1, &self.vbo);
        gl.glDeleteBuffers(1, &self.ibo);
        gl.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn render(self: *ZephyrGuiRenderer, ctx: *GuiContext, width: i32, height: i32) void {
        const dl = &ctx.draw_list;
        const vertices = dl.getVertices();
        const indices = dl.getIndices();
        const commands = dl.getCommands();

        if (vertices.len == 0 or commands.len == 0) {
            return;
        }

        // Save current OpenGL state
        var prev_blend: i32 = undefined;
        gl.glGetIntegerv(gl.GL_BLEND, &prev_blend);
        var prev_depth_test: i32 = undefined;
        gl.glGetIntegerv(gl.GL_DEPTH_TEST, &prev_depth_test);

        // Set up state for 2D GUI rendering
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
        gl.glDisable(gl.GL_DEPTH_TEST);

        gl.glUseProgram(self.shader);

        // Use framebuffer size for viewport
        gl.glViewport(0, 0, width, height);

        // Use logical coordinates for projection
        const logical_width = @as(f32, @floatFromInt(width)) / ctx.content_scale_x;
        const logical_height = @as(f32, @floatFromInt(height)) / ctx.content_scale_y;

        var proj: [16]f32 = ortho(0, logical_width, logical_height, 0, -1, 1);
        gl.glUniformMatrix4fv(self.proj_loc, 1, gl.GL_FALSE, &proj);
        gl.glUniform1i(self.tex_loc, 0);

        // Bind VAO and upload data
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(Vertex)), vertices.ptr, gl.GL_DYNAMIC_DRAW);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), indices.ptr, gl.GL_DYNAMIC_DRAW);

        gl.glActiveTexture(gl.GL_TEXTURE0);

        for (commands) |cmd| {
            if (cmd.elem_count == 0) continue;

            if (cmd.texture != 0) {
                const tex_id: u32 = @intCast(cmd.texture);
                gl.glBindTexture(gl.GL_TEXTURE_2D, tex_id);
            }

            const offset_ptr: ?*const anyopaque = @ptrFromInt(cmd.index_offset * @sizeOf(u32));
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(cmd.elem_count), gl.GL_UNSIGNED_INT, offset_ptr);
        }

        // Restore previous state
        if (prev_blend == 0) gl.glDisable(gl.GL_BLEND);
        if (prev_depth_test != 0) gl.glEnable(gl.GL_DEPTH_TEST);
    }

    /// Creates a zgui.Renderer interface backed by this implementation
    pub fn createInterface(self: *ZephyrGuiRenderer) Renderer {
        return Renderer.init(
            self,
            rendererInit,
            rendererRender,
            rendererCreateTexture,
            rendererDeleteTexture,
            rendererWrapTexture,
            rendererDeinit,
        );
    }
};

fn setupBuffers(r: *ZephyrGuiRenderer) void {
    gl.glGenVertexArrays(1, &r.vao);
    gl.glGenBuffers(1, &r.vbo);
    gl.glGenBuffers(1, &r.ibo);

    gl.glBindVertexArray(r.vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, r.vbo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, r.ibo);

    const stride = @sizeOf(Vertex);

    // Position (vec2)
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));

    // UV (vec2)
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(8));

    // Color (vec4 ubyte normalized)
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @ptrFromInt(16));

    r.proj_loc = gl.glGetUniformLocation(r.shader, "u_projection");
    r.tex_loc = gl.glGetUniformLocation(r.shader, "uTexture");
}

fn createShader() u32 {
    const vs_src =
        \\#version 330 core
        \\layout (location = 0) in vec2 in_pos;
        \\layout (location = 1) in vec2 in_uv;
        \\layout (location = 2) in vec4 in_color;
        \\
        \\uniform mat4 u_projection;
        \\
        \\out vec2 vUV;
        \\out vec4 vColor;
        \\
        \\void main() {
        \\    vUV = in_uv;
        \\    vColor = in_color;
        \\    gl_Position = u_projection * vec4(in_pos.xy, 0, 1);
        \\}
    ;

    const fs_src =
        \\#version 330 core
        \\in vec2 vUV;
        \\in vec4 vColor;
        \\
        \\uniform sampler2D uTexture;
        \\
        \\layout (location = 0) out vec4 out_color;
        \\
        \\void main() {
        \\    // Check if this is non-textured geometry (default UV is 1.0, 0.0)
        \\    if (vUV.x >= 0.99 && vUV.y <= 0.01) {
        \\        // Solid color rendering (for rectangles, shapes, etc.)
        \\        out_color = vColor;
        \\    } else {
        \\        vec4 texColor = texture(uTexture, vUV.st);
        \\        // If texture has color (G or B channels > 0.1), it's a full-color image
        \\        // Otherwise, it's text (single red channel used for alpha)
        \\        if (texColor.g > 0.1 || texColor.b > 0.1) {
        \\            // Full-color image rendering (use RGBA from texture)
        \\            out_color = texColor * vColor;
        \\        } else {
        \\            // Text rendering (use only red channel for alpha)
        \\            out_color = vec4(vColor.rgb, vColor.a * texColor.r);
        \\        }
        \\    }
        \\}
    ;

    const vs_ptrs = [_][*c]const u8{@ptrCast(vs_src)};
    const fs_ptrs = [_][*c]const u8{@ptrCast(fs_src)};

    const vs = gl.glCreateShader(gl.GL_VERTEX_SHADER);
    const fs = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);

    gl.glShaderSource(vs, 1, &vs_ptrs, null);
    gl.glCompileShader(vs);

    var success: i32 = 0;
    gl.glGetShaderiv(vs, gl.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetShaderInfoLog(vs, 1024, null, &log);
        std.debug.print("Vertex shader compilation failed:\n{s}\n", .{log});
    }

    gl.glShaderSource(fs, 1, &fs_ptrs, null);
    gl.glCompileShader(fs);

    gl.glGetShaderiv(fs, gl.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetShaderInfoLog(fs, 1024, null, &log);
        std.debug.print("Fragment shader compilation failed:\n{s}\n", .{log});
    }

    const prog = gl.glCreateProgram();
    gl.glAttachShader(prog, vs);
    gl.glAttachShader(prog, fs);
    gl.glLinkProgram(prog);

    gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetProgramInfoLog(prog, 1024, null, &log);
        std.debug.print("Shader program linking failed:\n{s}\n", .{log});
    }

    gl.glDeleteShader(vs);
    gl.glDeleteShader(fs);

    return prog;
}

fn ortho(l: f32, r: f32, b: f32, t: f32, n: f32, f: f32) [16]f32 {
    const rl = r - l;
    const tb = t - b;
    const fn_ = f - n;

    return .{
        2.0 / rl,       0.0,            0.0,           0.0,
        0.0,            2.0 / tb,       0.0,           0.0,
        0.0,            0.0,            -2.0 / fn_,    0.0,
        -(r + l) / rl,  -(t + b) / tb,  -(f + n) / fn_, 1.0,
    };
}

// Renderer interface wrapper functions
fn rendererInit(context: *anyopaque) void {
    _ = context;
}

fn rendererRender(context: *anyopaque, gui_ctx: *GuiContext, width: i32, height: i32) void {
    const self: *ZephyrGuiRenderer = @ptrCast(@alignCast(context));
    self.render(gui_ctx, width, height);
}

fn rendererCreateTexture(context: *anyopaque, width: i32, height: i32, format: TextureFormat, data: [*]const u8) TextureHandle {
    _ = context;

    var tex: u32 = 0;
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    const gl_format: c_uint = switch (format) {
        .r8 => gl.GL_RED,
        .rgba8 => gl.GL_RGBA,
    };

    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, @intCast(gl_format), width, height, 0, gl_format, gl.GL_UNSIGNED_BYTE, data);

    return @intCast(tex);
}

fn rendererDeleteTexture(context: *anyopaque, texture: TextureHandle) void {
    _ = context;
    var tex: u32 = @intCast(texture);
    gl.glDeleteTextures(1, &tex);
}

fn rendererWrapTexture(context: *anyopaque, texture_id: u32, width: i32, height: i32) TextureHandle {
    _ = context;
    _ = width;
    _ = height;
    return @intCast(texture_id);
}

fn rendererDeinit(context: *anyopaque) void {
    const self: *ZephyrGuiRenderer = @ptrCast(@alignCast(context));
    self.deinit();
}
