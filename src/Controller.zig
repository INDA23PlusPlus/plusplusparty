const std = @import("std");
const rl = @import("raylib");
const input = @import("input.zig");
const constants = @import("constants.zig");

const Controller = @This();
pub const DefaultControllers: [constants.max_controller_count]Controller = [_]Controller{.{}} ** constants.max_controller_count;

const AssignmentState = enum {
    unassigned, assigned, wants_assignment,
};

// TODO: player_index would be a better name
input_index: usize = std.math.maxInt(usize),

assignment_state: AssignmentState = AssignmentState.unassigned,
polled_state: input.PlayerInputState = input.PlayerInputState{},

pub inline fn isAssigned(self: Controller) bool {
    return self.assignment_state == .assigned;
}

pub fn wantsToJoin(controller: Controller) bool {
    return controller.polled_state.button_a.is_down() or controller.polled_state.button_b.is_down();
}

inline fn fourBoolsToDirection(up: bool, down: bool, left: bool, right: bool) input.InputDirection {
    if (up and !down) {
        if (left and !right) {
            return .NorthWest;
        } else if (right and !left) {
            return .NorthEast;
        } else {
            return .North;
        }
    } else if (down and !up) {
        if (left and !right) {
            return .SouthWest;
        } else if (right and !left) {
            return .SouthEast;
        } else {
            return .South;
        }
    } else {
        if (left and !right) {
            return .West;
        } else if (right and !left) {
            return .East;
        } else {
            return .None;
        }
    }
}

inline fn keyboardKeyToButtonState(key: rl.KeyboardKey) input.ButtonState {
    if (rl.isKeyUp(key)) {
        if (rl.isKeyReleased(key)) return .Released;

        return .NotHeld;
    }

    if (rl.isKeyPressed(key)) return .Pressed;

    return .Held;
}

inline fn gamepadButtonToButtonState(gamepad: i32, button: rl.GamepadButton) input.ButtonState {
    if (rl.isGamepadButtonUp(gamepad, button)) {
        if (rl.isGamepadButtonReleased(gamepad, button)) return .Released;

        return .NotHeld;
    }

    if (rl.isGamepadButtonPressed(gamepad, button)) return .Pressed;

    return .Held;
}

inline fn pollKeyboardDPads(key_up: rl.KeyboardKey, key_down: rl.KeyboardKey, key_left: rl.KeyboardKey, key_right: rl.KeyboardKey) input.InputDirection {
    const up = rl.isKeyDown(key_up);
    const down = rl.isKeyDown(key_down);
    const left = rl.isKeyDown(key_left);
    const right = rl.isKeyDown(key_right);
    return fourBoolsToDirection(up, down, left, right);
}

fn pollKeyboard1(previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_up, rl.KeyboardKey.key_down, rl.KeyboardKey.key_left, rl.KeyboardKey.key_right);
    const a = keyboardKeyToButtonState(rl.KeyboardKey.key_left_alt); // pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_z), previous.button_a);
    const b = keyboardKeyToButtonState(rl.KeyboardKey.key_left_control); // pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_x), previous.button_b);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
}

fn pollKeyboard2(previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_r, rl.KeyboardKey.key_f, rl.KeyboardKey.key_d, rl.KeyboardKey.key_g);
    const a = keyboardKeyToButtonState(rl.KeyboardKey.key_s);
    const b = keyboardKeyToButtonState(rl.KeyboardKey.key_a);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
}

fn pollGamepad(gamepad: i32, previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    if (!rl.isGamepadAvailable(gamepad)) return .{ .dpad = .Disconnected };

    const a = gamepadButtonToButtonState(gamepad, rl.GamepadButton.gamepad_button_right_face_down); // pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down), previous.button_a);
    const b = gamepadButtonToButtonState(gamepad, rl.GamepadButton.gamepad_button_right_face_right); // pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right), previous.button_b);

    const up = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_up);
    const down = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_down);
    const left = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_left);
    const right = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_right);

    const dpad = fourBoolsToDirection(up, down, left, right);

    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
}

/// Polls the state of all input devices possible.
/// It will return the amount of players that this client wants to own.
pub fn pollAll(controllers: []Controller, previous: input.AllPlayerButtons) u32 {
    var wanted_player_count: u32 = 0;

    for (controllers, 0..) |*controller, nth_controller| {
        const previous_buttons = if (controller.isAssigned()) previous[controller.input_index] else input.PlayerInputState{};
        controller.polled_state = switch (nth_controller) {
            0 => pollKeyboard1(previous_buttons),
            1 => pollKeyboard2(previous_buttons),
            else => pollGamepad(@intCast(nth_controller - 2), previous_buttons),
        };

        if (controller.assignment_state == .unassigned) {
            if (controller.wantsToJoin()) {
                controller.assignment_state = .wants_assignment;
                wanted_player_count += 1;
            }
        } else {
            wanted_player_count += 1;
        }
    }

    return wanted_player_count;
}

pub fn autoAssign(controllers: []Controller, owned_players: input.PlayerBitSet) void {
    var available = owned_players;
    for (controllers) |controller| {
        if (controller.isAssigned()) {
            available.unset(controller.input_index);
        }
    }

    for (controllers) |*controller| {
        if (controller.assignment_state == .wants_assignment) {
            if (available.findFirstSet()) |player_index| {
                available.unset(player_index);
                controller.input_index = player_index;
                controller.assignment_state = .assigned;
            }
        }
    }
}
