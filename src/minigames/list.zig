const std = @import("std");
const menu = @import("menu.zig");
const morsecode = @import("morsecode.zig");
const tron = @import("tron.zig");
const smash = @import("smash.zig");
const hot_n_steamy = @import("hot_n_steamy.zig");
const kattis = @import("kattis.zig");
const lobby = @import("lobby.zig");
const gamewheel = @import("gamewheel.zig");
const example = @import("example.zig");
const scoreboard = @import("scoreboard.zig");
const wait_for_input = @import("wait_for_input.zig");
const winscreen = @import("winscreen.zig");

const Minigame = @import("Minigame.zig");

/// Create a list of Minigames.
pub const list = [_]Minigame{
    .{
        .name = "wait_for_input",
        .update = wait_for_input.update,
        .init = wait_for_input.init,
    },
    .{
        .name = "menu",
        .update = menu.update,
        .init = menu.init,
    },
    .{
        .name = "lobby",
        .update = lobby.update,
        .init = lobby.init,
    },
    .{
        .name = "example",
        .update = example.update,
        .init = example.init,
    },
    .{
        .name = "scoreboard",
        .update = scoreboard.update,
        .init = scoreboard.init,
    },

    .{
        .name = "winscreen",
        .update = winscreen.update,
        .init = winscreen.init,
    },
    .{
        .name = "gamewheel",
        .update = gamewheel.update,
        .init = gamewheel.init,
    },
    // All minigames that can be picked by the spinning wheel should
    // come after the "gamewheel" minigame.
    .{
        .name = "morsecode",
        .update = morsecode.update,
        .init = morsecode.init,
    },
    .{
        .name = "tron",
        .update = tron.update,
        .init = tron.init,
    },
    .{
        .name = "smash",
        .update = smash.update,
        .init = smash.init,
    },
    .{
        .name = "hns",
        .update = hot_n_steamy.update,
        .init = hot_n_steamy.init,
    },
    .{
        .name = "kattis",
        .update = kattis.update,
        .init = kattis.init,
    },
    // .{
    //     .name = "example",
    //     .update = example.update,
    //     .init = example.init,
    // },
};

fn findPreferredMinigameID(preferred_minigame: []const u8) u32 {
    for (list, 0..) |mg, i| {
        if (std.mem.eql(u8, mg.name, preferred_minigame)) {
            return @truncate(i);
        }
    }
    @panic("unknown minigame");
}
