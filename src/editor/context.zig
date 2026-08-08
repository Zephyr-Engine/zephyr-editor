const std = @import("std");

const action_mod = @import("actions.zig");
const Command = @import("command.zig").Command;
const Session = @import("session.zig");

const EditorContext = @This();

allocator: std.mem.Allocator,
session: Session = .{},
actions: action_mod.Registry,

pub fn create(allocator: std.mem.Allocator) !*EditorContext {
    const context = try allocator.create(EditorContext);
    errdefer allocator.destroy(context);
    context.* = .{
        .allocator = allocator,
        .actions = action_mod.Registry.init(allocator),
    };
    errdefer context.actions.deinit();
    try context.registerActions();

    return context;
}

pub fn destroy(self: *EditorContext) void {
    const allocator = self.allocator;
    self.actions.deinit();
    allocator.destroy(self);
}

pub fn actionRegistry(self: *EditorContext) *action_mod.Registry {
    return &self.actions;
}

fn registerActions(self: *EditorContext) !void {
    try self.actions.register(action_mod.ids.play, bindCommand("Play", &self.session, .play));
    try self.actions.register(action_mod.ids.pause, bindCommand("Pause", &self.session, .pause));
    try self.actions.register(action_mod.ids.stop, bindCommand("Stop", &self.session, .stop));
}

fn bindCommand(comptime label: []const u8, session: *Session, comptime command: Command) action_mod.Action {
    return action_mod.Action.bind(label, session, commandAction(command)).withEnabled(commandEnabled(command));
}

fn commandAction(comptime command: Command) fn (*Session) void {
    return struct {
        fn execute(session: *Session) void {
            _ = session.handle(command);
        }
    }.execute;
}

fn commandEnabled(comptime command: Command) fn (*Session) bool {
    return struct {
        fn enabled(session: *Session) bool {
            return session.canHandle(command);
        }
    }.enabled;
}

test "editor context owns session-backed action state" {
    var context = try EditorContext.create(std.testing.allocator);
    defer context.destroy();

    try std.testing.expect(context.actions.enabled(action_mod.ids.play));
    try std.testing.expect(!context.actions.enabled(action_mod.ids.pause));
    try std.testing.expect(!context.actions.enabled(action_mod.ids.stop));

    try std.testing.expect(context.actions.invoke(action_mod.ids.play));
    try std.testing.expect(!context.actions.enabled(action_mod.ids.play));
    try std.testing.expect(context.actions.enabled(action_mod.ids.pause));
    try std.testing.expect(context.actions.enabled(action_mod.ids.stop));
}
