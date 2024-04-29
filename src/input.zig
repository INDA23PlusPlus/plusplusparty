const constants = @import("constants.zig");
const std = @import("std");

// TODO: We could add a NoneHeld in order to skip checking previous frames for 'instant' dpad movement.
pub const InputDirection = enum(u4) { None, East, North, West, South, NorthEast, NorthWest, SouthWest, SouthEast, Disconnected };
pub const ButtonState = enum(u2) {
    Pressed,
    Held,
    Released,
    pub fn is_down(self: ButtonState) bool {
        // Currently only used in one place...
        return self == .Pressed or self == .Held;
    }
};
pub const PlayerInputState = packed struct {
    dpad: InputDirection = .Disconnected,
    button_a: ButtonState = .Released,
    button_b: ButtonState = .Released,

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
pub const IsLocalBitfield = std.bit_set.IntegerBitSet(constants.max_player_count);
pub const default_input_state = [_]PlayerInputState{.{}} ** constants.max_player_count;

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
};
