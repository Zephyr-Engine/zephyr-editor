const std = @import("std");
const zp = @import("zephyr_runtime");

const EditorCamera = zp.EditorCamera;
const MeshHandle = zp.MeshHandle;
const Shader = zp.Shader;
const Input = zp.Input;
const ZMesh = zp.ZMesh;
const Vec3 = zp.Vec3;
const gl = zp.gl;

const vs_src: [*c]const u8 = @embedFile("assets/shaders/vertex.glsl");
const fs_src: [*c]const u8 = @embedFile("assets/shaders/fragment.glsl");

const speed: f32 = 2.0;

pub const GameScene = struct {
    allocator: std.mem.Allocator,
    mesh_handle: MeshHandle,
    shader: Shader,
    editor_camera: EditorCamera,

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator, io: std.Io) !void {
        std.log.info("Starting up game scene", .{});

        self.editor_camera = EditorCamera.init(
            Vec3.new(0, 0, 3),
            16.0 / 9.0,
        );
        self.allocator = allocator;

        const cwd = std.Io.Dir.cwd();
        const mesh_file = try cwd.openFile(io, "src/output/monkey.zmesh", .{});
        var mesh = try ZMesh.read(allocator, io, mesh_file);
        defer mesh.deinit(allocator);

        self.mesh_handle = try MeshHandle.loadFromZMesh(mesh);
        self.shader = try Shader.init(allocator, vs_src, fs_src);

        gl.glEnable(gl.GL_DEPTH_TEST);
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) !void {
        _ = delta_time;
        self.editor_camera.update();

        gl.glClearColor(0.4, 0.4, 0.4, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        self.shader.setUniform("u_view", self.editor_camera.camera.viewMatrix());
        self.shader.setUniform("u_projection", self.editor_camera.camera.projectionMatrix());
        self.mesh_handle.draw();
    }

    pub fn onEvent(self: *GameScene, e: zp.ZEvent) !void {
        self.editor_camera.processEvent(e);
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) !void {
        _ = allocator;
        std.log.info("Game Scene Cleaning up...", .{});
        self.shader.deinit();
        self.mesh_handle.deinit();
    }
};
