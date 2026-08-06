const Command = @import("../editor/command.zig").Command;
const log = @import("../utilities/log.zig");

pub const PlayState = enum {
    Play,
    Pause,
    Stop,

    pub const Transition = struct {
        from: PlayState,
        to: PlayState,
    };

    pub fn apply(current: PlayState, command: Command) ?Transition {
        const next: PlayState = switch (command) {
            .play => .Play,
            .pause => if (current == .Play) .Pause else current,
            .stop => .Stop,
        };

        if (next == current) {
            return null;
        }

        log.info("Play state transition: {} -> {}", .{ current, next });
        return .{ .from = current, .to = next };
    }
};

const testing = @import("std").testing;

test "play state accepts only meaningful transitions" {
    try testing.expectEqual(PlayState.Play, PlayState.Stop.apply(.play).?.to);
    try testing.expectEqual(PlayState.Pause, PlayState.Play.apply(.pause).?.to);
    try testing.expectEqual(PlayState.Stop, PlayState.Pause.apply(.stop).?.to);
    try testing.expect(PlayState.Stop.apply(.pause) == null);
    try testing.expect(PlayState.Stop.apply(.stop) == null);
}
