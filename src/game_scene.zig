const std = @import("std");
const zp = @import("zephyr_runtime");

const VertexArray = zp.VertexArray;
const MeshHandle = zp.MeshHandle;
const Shader = zp.Shader;
const Input = zp.Input;
const ZMesh = zp.ZMesh;
const Vec2 = zp.Vec2;
const gl = zp.gl;

const vs_src: [*c]const u8 = @embedFile("assets/shaders/vertex.glsl");
const fs_src: [*c]const u8 = @embedFile("assets/shaders/fragment.glsl");

const speed: f32 = 2.0;

pub const GameScene = struct {
    allocator: std.mem.Allocator,
    mesh_handle: MeshHandle,
    shader: Shader,
    offset: Vec2,

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator, io: std.Io) !void {
        std.log.info("Starting up game scene", .{});

        self.offset = .{
            .x = 0,
            .y = 0,
        };
        self.allocator = allocator;

        const cwd = std.Io.Dir.cwd();
        const mesh_file = try cwd.openFile(io, "src/output/triangle.zmesh", .{});
        var mesh = try ZMesh.read(allocator, io, mesh_file);
        defer mesh.deinit(allocator);

        self.mesh_handle = try MeshHandle.loadFromZMesh(mesh);
        self.shader = try Shader.init(allocator, vs_src, fs_src);
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
        self.mesh_handle.draw();
    }

    pub fn onEvent(self: *GameScene, e: zp.ZEvent) !void {
        _ = self;
        _ = e;
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) !void {
        _ = allocator;
        std.log.info("Game Scene Cleaning up...", .{});
        self.shader.deinit();
        self.mesh_handle.deinit();
    }
};
