/// The purpose of this minigame is to use metadata to switch over to a preferred minigame.
/// This is done so that we do not need to call init() in two places. Do not put important stuff in this
/// minigame's init() as it is never called as a consequences. In fact, expect almost everything to not be
/// initialized properly.
/// The minigame will wait 4 ticks, then start checking if enough
/// players exists (or if we wish to switch to the lobby).

const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const constants = @import("../constants.zig");
const std = @import("std");

const Invariables = @import("../Invariables.zig");

pub fn init(_: *simulation.Simulation, _: input.Timeline) !void {}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    // TODO: Spawn a sprite informing users they should press Z/X (A/B) to connect a player.
    // TODO: Also the mainmenu minigame should always have a connected controller somehow.

    var players_connected: u32 = 0;
    for (timeline.latest()) |player| {
        if (player.is_connected()) {
            players_connected += 1;
        }
    }

    const wants_lobby = sim.meta.preferred_minigame_id == constants.minigame_lobby;

    if (sim.meta.minigame_counter >= 4) {
        if (players_connected >= sim.meta.min_players or wants_lobby) {
            sim.meta.minigame_id = sim.meta.preferred_minigame_id;
        }
    }
    sim.meta.minigame_counter += 1;
}
