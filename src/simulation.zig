const ecs = @import("ecs/ecs.zig");
const constants = @import("constants.zig");
const std = @import("std");
const input = @import("input.zig");
const Invariables = @import("Invariables.zig");

const seed = 555;

/// Data that is kept between minigames (such as seed, scores, etc)
pub const Metadata = struct {
    ticks_elapsed: u64 = 0,

    /// What minigame the minigame known as "preferred" will jump to.
    /// Note that if it is set to 0, you will be presented with a whitescreen
    /// as that is the current ID of "preferred".
    preferred_minigame_id: u32 = 0,

    /// How many players to wait for until leaving the wait_for_input minigame.
    min_players: u16 = 0,

    minigame_id: u32 = 0,
    minigame_prng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(seed),
    minigame_timer: u32 = 0,
    minigame_counter: u32 = 0,

    /// Score realted things:
    global_score: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
    minigame_placements: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
};

// TODO: Convert simulation.zig into Simulation.zig
pub const Simulation = struct {
    world: ecs.world.World = .{},
    meta: Metadata = .{},
};

/// All the errors that may happen during simulation.
pub const SimulationError = ecs.world.WorldError;

/// Simulate one tick in the game world.
/// All generic game code will be called from this function and should not
/// use anything outside of the world or the input frame. Failing to do so
/// will lead to inconsistencies.
pub fn simulate(sim: *Simulation, input_state: input.Timeline, rt: Invariables) !void {
    const frame_start_minigame = sim.meta.minigame_id;

    sim.meta.ticks_elapsed += 1;

    try rt.minigames_list[sim.meta.minigame_id].update(sim, input_state, rt);

    // Handles transitions between minigames.
    if (frame_start_minigame != sim.meta.minigame_id) {
        sim.world.reset();
        sim.meta.minigame_timer = 0;
        sim.meta.minigame_counter = 0;
        sim.meta.minigame_prng.seed(seed + sim.meta.ticks_elapsed);
        try rt.minigames_list[sim.meta.minigame_id].init(sim, input_state);
    }
}
