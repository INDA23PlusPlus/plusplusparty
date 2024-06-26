const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const input = @import("../input.zig");
const constants = @import("../constants.zig");

pub const Animation = enum {
    Default,
    KattisIdle,
    KattisRun,
    KattisFly,
    HnsFly,
    TronSkull,
    SmashIdle,
    SmashRun,
    SmashJump,
    SmashFall,
    SmashRise,
    SmashLand,
    SmashCrouch,
    SmashHit,
    SmashAttack,
    SmashBlock,
    SmashJumpSmoke,
    SmashAttackSmoke,
    SmashDeath,
    SmashSun,
    Gamewheel,
    Crown,
    CatPortrait,
    CatPortraitDie,
    ScoreboardBackground,
};

pub fn data(animation: Animation) []const Frame {
    return switch (animation) {
        .Default => &frames_default,
        .KattisIdle => &frames_kattis_idle,
        .KattisRun => &frames_kattis_run,
        .KattisFly => &frames_kattis_fly,
        .HnsFly => &frames_hns_fly,
        .TronSkull => &frames_tron_skull,
        .SmashIdle => &frames_smash_idle,
        .SmashRun => &frames_smash_run,
        .SmashJump => &frames_smash_jump,
        .SmashRise => &frames_smash_rise,
        .SmashFall => &frames_smash_fall,
        .SmashLand => &frames_smash_land,
        .SmashCrouch => &frames_smash_crouch,
        .SmashHit => &frames_smash_hit,
        .SmashAttack => &frames_smash_attack,
        .SmashBlock => &frames_smash_block,
        .SmashJumpSmoke => &frames_smash_jump_smoke,
        .SmashAttackSmoke => &frames_smash_attack_smoke,
        .SmashDeath => &frames_smash_death,
        .SmashSun => &frames_smash_sun,
        .Gamewheel => &frames_gamewheel,
        .Crown => &frames_crown,
        .CatPortrait => &frames_portrait,
        .CatPortraitDie => &frames_portrait_die,
        .ScoreboardBackground => &frames_scoreboard_background,
    };
}

const frames_default: [1]Frame = .{
    Frame.init(0, 0),
};

const frames_kattis_idle: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(2, 0),
    Frame.init(3, 0),
};

const frames_kattis_run: [3]Frame = .{
    Frame.init(0, 1),
    Frame.init(1, 1),
    Frame.init(2, 1),
};

const frames_kattis_fly: [4]Frame = .{
    Frame.init(0, 2),
    Frame.init(1, 2),
    Frame.init(2, 2),
    Frame.init(3, 2),
};

const frames_hns_fly: [3]Frame = .{
    Frame.init(2, 5),
    Frame.init(4, 5),
    Frame.init(6, 5),
};

const frames_tron_skull: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(2, 0),
    Frame.init(3, 0),
};

const frames_smash_idle: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(2, 0),
    Frame.init(4, 0),
    Frame.init(6, 0),
};

const frames_smash_run: [8]Frame = .{
    Frame.init(0, 4),
    Frame.init(2, 4),
    Frame.init(4, 4),
    Frame.init(6, 4),
    Frame.init(8, 4),
    Frame.init(10, 4),
    Frame.init(12, 4),
    Frame.init(14, 4),
};

const frames_smash_jump: [2]Frame = .{
    Frame.init(2, 8),
    Frame.init(4, 8),
};

const frames_smash_rise: [1]Frame = .{
    Frame.init(4, 8),
};

const frames_smash_fall: [2]Frame = .{
    Frame.init(6, 8),
    Frame.init(8, 8),
};

const frames_smash_land: [2]Frame = .{
    Frame.init(10, 8),
    Frame.init(12, 8),
};

const frames_smash_attack: [3]Frame = .{
    Frame.init(4, 7),
    Frame.init(4, 7),
    Frame.init(6, 7),
};

const frames_smash_jump_smoke: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(2, 0),
    Frame.init(4, 0),
    Frame.init(6, 0),
};

const frames_smash_attack_smoke: [5]Frame = .{
    Frame.init(0, 0),
    Frame.init(2, 0),
    Frame.init(4, 0),
    Frame.init(6, 0),
    Frame.init(8, 0),
};

const frames_smash_crouch: [4]Frame = .{
    Frame.init(0, 6),
    Frame.init(2, 6),
    Frame.init(4, 6),
    Frame.init(6, 6),
};

const frames_smash_block: [4]Frame = .{
    Frame.init(0, 2),
    Frame.init(2, 2),
    Frame.init(4, 2),
    Frame.init(6, 2),
};

const frames_smash_hit: [1]Frame = .{
    Frame.init(8, 9),
};

const frames_smash_death: [5]Frame = .{
    Frame.init(0, 0),
    Frame.init(2, 0),
    Frame.init(4, 0),
    Frame.init(6, 0),
    Frame.init(8, 0),
};

const frames_smash_sun: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(4, 0),
    Frame.init(8, 0),
    Frame.init(12, 0),
};

const frames_gamewheel: [6]Frame = .{
    Frame.init(0, 0),
    Frame.init(16, 0),
    Frame.init(32, 0),
    Frame.init(48, 0),
    Frame.init(64, 0),
    Frame.init(80, 0),
};

const frames_crown: [18]Frame = .{
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(2, 0),
    Frame.init(3, 0),
    Frame.init(4, 0),
    Frame.init(5, 0),
    Frame.init(6, 0),
    Frame.init(7, 0),
    Frame.init(0, 1),
    Frame.init(1, 1),
    Frame.init(2, 1),
    Frame.init(3, 1),
    Frame.init(4, 1),
    Frame.init(5, 1),
    Frame.init(6, 1),
    Frame.init(7, 1),
    Frame.init(0, 2),
    Frame.init(1, 2),
};

const frames_portrait: [6]Frame = .{
    Frame.init(0, 0),
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(1, 0),
    Frame.init(0, 0),
    Frame.init(0, 0),
};

const frames_portrait_die: [2]Frame = .{
    Frame.init(2, 0),
    Frame.init(3, 0),
};

const frames_scoreboard_background: [4]Frame = .{
    Frame.init(0 * constants.world_width_tiles, 0),
    Frame.init(1 * constants.world_width_tiles, 0),
    Frame.init(2 * constants.world_width_tiles, 0),
    Frame.init(3 * constants.world_width_tiles, 0),
};

pub const Frame = struct {
    u: u32,
    v: u32,

    pub fn init(u: u32, v: u32) Frame {
        return Frame{ .u = u, .v = v };
    }
};
