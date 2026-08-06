const std = @import("std");

const PlayState = @import("../state/play_state.zig").PlayState;
const Command = @import("command.zig").Command;

const Session = @This();

play_state: PlayState = .Stop,

pub fn handle(self: *Session, command: Command) ?PlayState.Transition {
    const transition = self.play_state.apply(command) orelse return null;
    self.play_state = transition.to;
    return transition;
}

test "play commands update the session once per distinct transition" {
    var session: Session = .{};

    const started = session.handle(.play).?;
    try std.testing.expectEqual(PlayState.Stop, started.from);
    try std.testing.expectEqual(PlayState.Play, started.to);
    try std.testing.expect(session.handle(.play) == null);

    const paused = session.handle(.pause).?;
    try std.testing.expectEqual(PlayState.Pause, paused.to);
}
