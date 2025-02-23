const constants = @import("constants.zig");
const std = @import("std");

// TODO: We could add a NoneHeld in order to skip checking previous frames for 'instant' dpad movement.
// TODO: Fix the naming convention to follow Zig 0.12 (lowercase)...
pub const InputDirection = enum(u4) {
    None,
    East,
    North,
    West,
    South,
    NorthEast,
    NorthWest,
    SouthWest,
    SouthEast,
    Disconnected,
    pub fn shortDebugName(self: InputDirection) []const u8 {
        return switch (self) {
            .None => "**",
            .East => "E.",
            .West => "W.",
            .North => "N.",
            .South => "S.",
            .NorthWest => "NW",
            .NorthEast => "NE",
            .SouthWest => "SW",
            .SouthEast => "SE",
            .Disconnected => "--",
        };
    }
};
pub const ButtonState = enum(u2) {
    Pressed, // TODO: Fix the naming convention to follow Zig 0.12 (lowercase)...
    Held,
    Released,
    NotHeld,
    pub inline fn is_down(self: ButtonState) bool {
        // Currently only used in one place...
        return self == .Pressed or self == .Held;
    }
    pub inline fn is_up(self: ButtonState) bool {
        return self == .Released or self == .NotHeld;
    }
    pub inline fn prediction(self: ButtonState) ButtonState {
        return switch (self) {
            .Pressed, .Held => .Held,
            .Released, .NotHeld => .NotHeld,
        };
    }
};
pub const PlayerInputState = packed struct(u8) {
    dpad: InputDirection = .Disconnected,
    button_a: ButtonState = .NotHeld,
    button_b: ButtonState = .NotHeld,

    pub fn is_connected(self: PlayerInputState) bool {
        // TODO: Maybe it should be removed in the future once we've settled into an input struct we like...
        return self.dpad != .Disconnected;
    }

    pub fn horizontal(self: PlayerInputState) i32 {
        return switch (self.dpad) {
            .East, .NorthEast, .SouthEast => 1,
            .West, .NorthWest, .SouthWest => -1,
            else => 0,
        };
    }

    pub fn vertical(self: PlayerInputState) i32 {
        return switch (self.dpad) {
            .North, .NorthEast, .NorthWest => 1,
            .South, .SouthEast, .SouthWest => -1,
            else => 0,
        };
    }
};

pub const AllPlayerButtons = [constants.max_player_count]PlayerInputState;
pub const default_input_state: AllPlayerButtons = [_]PlayerInputState{.{}} ** constants.max_player_count;

// TODO: Find a better file for these.
pub const PlayerBitSet = std.bit_set.IntegerBitSet(constants.max_player_count);
pub const empty_player_bit_set = PlayerBitSet.initEmpty();
pub const full_player_bit_set = PlayerBitSet.initFull();

pub const Timeline = struct {
    // Normally one would not make a struct for just one variable.
    // But we want to create some nice helper functions for the timeline.
    buttons: []AllPlayerButtons,
    pub fn latest(self: Timeline) AllPlayerButtons {
        if (self.buttons.len == 0) {
            return default_input_state;
        }
        return self.buttons[self.buttons.len - 1];
    }

    pub fn horizontal_pressed(time: Timeline, player: usize) i32 {
        std.debug.assert(player < constants.max_player_count);
        if (time.buttons.len < 2) {
            return 0;
        }
        const b = time.buttons;
        const previous = b[time.buttons.len - 2][player].horizontal();
        const resulting = b[time.buttons.len - 1][player].horizontal();
        if (previous == resulting) {
            return 0;
        }
        return resulting;
    }

    pub fn vertical_pressed(time: Timeline, player: usize) i32 {
        std.debug.assert(player < constants.max_player_count);
        if (time.buttons.len < 2) {
            return 0;
        }
        const b = time.buttons;
        const previous = b[time.buttons.len - 2][player].vertical();
        const resulting = b[time.buttons.len - 1][player].vertical();
        if (previous == resulting) {
            return 0;
        }
        return resulting;
    }

    /// Returns the tick of the last time `button` was in `state`. Only queries `search_depth` ticks.
    pub fn buttonStateTick(time: Timeline, player: usize, comptime button: enum { a, b }, comptime state: ButtonState) ?usize {
        std.debug.assert(player < constants.max_player_count);

        const search_depth = 60;

        var i: usize = time.buttons.len;
        var j: usize = 0;

        while (i > 0 and j < search_depth) {
            i -= 1;
            j += 1;

            const s = switch (button) {
                .a => time.buttons[i][player].button_a,
                .b => time.buttons[i][player].button_b,
            };

            if (s == state) return i;
        }

        return null;
    }

    pub fn connectedPlayerCount(time: Timeline) usize {
        var i: usize = 0;

        for (time.latest()) |plr| {
            if (plr.is_connected()) i += 1;
        }

        return i;
    }
};

