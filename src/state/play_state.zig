const log = @import("../utilities/log.zig");

pub const PlayState = enum {
    Play,
    Pause,
    Stop,

    pub fn transition(from: PlayState, to: PlayState) PlayState {
        return switch (from) {
            .Play => switch (to) {
                .Play => .Play,
                .Pause => transitionToPause(),
                .Stop => transitionToStop(),
            },
            .Pause => switch (to) {
                .Play => transitionToPlay(),
                .Pause => .Pause,
                .Stop => transitionToStop(),
            },
            .Stop => switch (to) {
                .Play => transitionToPlay(),
                .Pause => transitionToPause(),
                .Stop => .Stop,
            },
        };
    }
};

fn transitionToPlay() PlayState {
    log.info("Playing game", .{});
    return .Play;
}

fn transitionToPause() PlayState {
    log.info("Pausing game", .{});
    return .Pause;
}

fn transitionToStop() PlayState {
    log.info("Stopping game", .{});
    return .Stop;
}
