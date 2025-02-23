// TODO: InputMerger would be a more obvious name.

const std = @import("std");
const input = @import("input.zig");
const constants = @import("constants.zig");
const Controller = @import("Controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.AllPlayerButtons);
const PlayerBitSetArrayList = std.ArrayListUnmanaged(input.PlayerBitSet);

rw_lock: std.Thread.RwLock = .{},
buttons: InputStateArrayList,
is_certain: PlayerBitSetArrayList,
is_local: PlayerBitSetArrayList,

prediction_fix_start: u64 = 1,
prediction_fix_end: u64 = 1,

pub fn init(allocator: std.mem.Allocator) !Self {
    // We append one to each array because extendTimeline() must have at least one frame available
    // such that it can be used as inspiration for the rest of the timeline.
    var buttons = try InputStateArrayList.initCapacity(allocator, 1024);
    try buttons.append(allocator, input.default_input_state);

    // We are always certain of the zero frame as changes to it
    // should be ignored.
    var is_certain = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    try is_certain.append(allocator, input.full_player_bit_set);

    // First input was not created locally. It is just universally known.
    var is_local = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    try is_local.append(allocator, input.empty_player_bit_set);

    return .{
        .buttons = buttons,
        .is_certain = is_certain,
        .is_local = is_local,
    };
}

/// Includes a region to be re-predicted.
/// If this function isn't called where predictions are 
/// made a desynch can happen.
fn mustFixPrediction(self: *Self, start: u64, end: u64) void {
    self.prediction_fix_start = @min(self.prediction_fix_start, start);
    self.prediction_fix_end = @max(self.prediction_fix_end, end);
}

/// Does prediciton for the area that might contain
/// outdated predicitons.
/// Returns std.math.maxInt(u64) if no predictions were made.
pub fn fixInputPredictions(self: *Self) u64 {
    var rewind_to_tick: u64 = std.math.maxInt(u64);
    var guess_buttons = input.default_input_state;


    if (self.prediction_fix_start >= self.prediction_fix_end) {
        // Nothing to predict.
        return rewind_to_tick;
    }

    // We actually start one tick before so that we can be sure that the
    // first tick we process is safe to guess from.
    const start = self.prediction_fix_start - 1;

    for(start..self.prediction_fix_end) |input_index| {
        for (0..constants.max_player_count) |player| {
            if (self.is_certain.items[input_index].isSet(player) or input_index == start) {
                // We are sure of this input. So we may use it to inspire future predicitions.
                guess_buttons[player] = self.buttons.items[input_index][player];

                // It doesn't make sense for the prediction
                // to be that the player keeps button mashing at a pefect
                // 1 click per tick. So we adjust it.
                guess_buttons[player].button_a = guess_buttons[player].button_a.prediction();
                guess_buttons[player].button_b = guess_buttons[player].button_b.prediction();
            } else if (!std.meta.eql(self.buttons.items[input_index][player], guess_buttons[player])) {
                // Old prediction is different from new prediction. So we may change.
                self.buttons.items[input_index][player] = guess_buttons[player];
                rewind_to_tick = @min(rewind_to_tick, input_index);
            }
        }
    }

    self.prediction_fix_start = std.math.maxInt(u64);
    self.prediction_fix_end = 0;

    return rewind_to_tick;
}

pub fn extendTimeline(self: *Self, allocator: std.mem.Allocator, tick: u64) !void {
    const new_len = tick + 1;

    if (new_len < self.buttons.items.len) {
        // No need to extend the timeline.
        return;
    }

    const start = self.buttons.items.len;

    try self.buttons.ensureTotalCapacity(allocator, new_len);
    self.buttons.items.len = new_len;

    try self.is_certain.ensureTotalCapacity(allocator, new_len);
    self.is_certain.items.len = new_len;

    try self.is_local.ensureTotalCapacity(allocator, new_len);
    self.is_local.items.len = new_len;

    for (self.buttons.items[start..]) |*frame| {
        frame.* = input.default_input_state;
    }

    for (self.is_certain.items[start..]) |*frame| {
        // We are always unsure when we are guessing.
        frame.* = input.empty_player_bit_set;
    }

    for (self.is_local.items[start..]) |*frame| {
        // No inputs have been set yet.
        frame.* = input.empty_player_bit_set;
    }

    self.mustFixPrediction(start, new_len);
}

pub fn localUpdate(self: *Self, controllers: []Controller, tick: u64) !void {
    // Make sure that extendTimeline() is called before.
    std.debug.assert(tick < self.buttons.items.len);

    var is_certain = self.is_certain.items[tick];
    var is_local = self.is_local.items[tick];
    for (controllers) |controller| {
        const player = controller.input_index;
        if (controller.isAssigned()) {
            if (is_certain.isSet(player)) {
                std.debug.print("warning local client is attempting to override previous input\n", .{});
                continue;
            }
            self.buttons.items[tick][player] = controller.polled_state;
            is_certain.set(player);
            is_local.set(player);

        }
    }
    self.is_certain.items[tick] = is_certain;
    self.is_local.items[tick] = is_local;

    self.mustFixPrediction(tick, tick + 1);
}

pub fn undoUpdate(self: *Self, player: u32, tick: u64) void {
    if (tick >= self.is_local.items.len) {
        // No point in undoing something outside of the current timeline.
        return;
    }

    // The server said it did not accept the local input. So undo this local input if it is local.
    if (self.is_local.items[tick].isSet(player)) {
        self.is_local.items[tick].unset(player);
        self.is_certain.items[tick].unset(player);

        // The mustFixPrediction call will ensure that we set a more reasonable guess for this input.
        self.mustFixPrediction(tick, tick + 1);
        std.debug.print("warning, local input was removed for player {} at {}\n", .{player, tick});
    }
}

/// Returns true if the timeline was changed by this call.
pub fn remoteUpdate(self: *Self, allocator: std.mem.Allocator, player: u32, new_state: input.PlayerInputState, tick: u64) !bool {
    try self.extendTimeline(allocator, tick);

    // We will not let local input override this input in the future.
    // It is locked in for consistency.
    // Setting this flag also lets us know that it is worth sending in the net-code.
    // We only set consistency for <tick> because future values are just "guesses".
    self.is_certain.items[tick].set(player);

    self.mustFixPrediction(tick, tick + 1);

    if (std.meta.eql(self.buttons.items[tick][player], new_state)) {
        return false;
    }

    self.buttons.items[tick][player] = new_state;

    return true;
}

pub fn createChecksum(self: *Self, until: u64) u32 {
    var hasher = std.hash.crc.Crc32.init();
    for (0.., self.buttons.items) |tick_index, buttons| {
        if (tick_index > until) {
            break;
        }
        for (buttons) |button| {
            const state: u8 = @intFromEnum(button.dpad);
            const button_a: u8 = @intFromEnum(button.button_a);
            const button_b: u8 = @intFromEnum(button.button_b);
            hasher.update(&[_]u8{ state, button_a, button_b });
        }
    }
    return hasher.final();
}

pub fn dumpInputs(self: *Self, until: u64, writer: anytype) !void {
    const checksum = self.createChecksum(until);
    try writer.print("input frames: {d}\n", .{@min(self.buttons.items.len, until)});
    for (0.., self.buttons.items, self.is_certain.items) |tick_index, inputs, is_certain| {
        if (tick_index > until) {
            break;
        }
        try writer.print("{d:0>4}:", .{tick_index});
        for (inputs, 0..) |inp, i| {
            const on = if (is_certain.isSet(i)) "+" else "?";
            const a: u8 = @intFromEnum(inp.button_a);
            const b: u8 = @intFromEnum(inp.button_a);
            try writer.print(" {s}{d}{d}({s})", .{ inp.dpad.shortDebugName(), a, b, on });
        }
        try writer.print("\n", .{});
    }
    try writer.print("checksum: {x}\n", .{checksum});
}
