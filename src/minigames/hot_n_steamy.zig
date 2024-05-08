const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const input = @import("../input.zig");
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const Vec2 = ecs.component.Vec2;
const F32 = ecs.component.F32;
const crown = @import("../crown.zig");

//TODO Remove this and change som RNG comes from ecs of metadata
var prng = std.rand.DefaultPrng.init(555);
const rand = prng.random();

const obstacle_height_base = 7;
const obstacle_height_delta = 6;
const player_gravity = Vec2.init(0, F32.init(1, 10));
const player_boost = Vec2.init(0, F32.init(-1, 4));
const vertical_obstacle_velocity = Vec2.init(-5, 0);
const horizontal_obstacle_velocity = Vec2.init(-8, 0);

const ObstacleKind = enum { ObstacleUpper, ObstacleLower, ObstacleBoth };

const background_layers = [_][]const u8{
    "assets/sky_background_0.png",
    "assets/sky_background_1.png",
    "assets/sky_background_2.png",
};

const background_scroll = [_]i16{ -1, -2, -3 };

fn spawnBackground(world: *ecs.world.World) !void {
    const n = @min(background_layers.len, background_scroll.len);
    for (0..n) |i| {
        for (0..2) |ix| {
            _ = try world.spawnWith(.{
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash(background_layers[i]),
                    .w = constants.world_width_tiles,
                    .h = constants.world_height_tiles,
                },
                ecs.component.Pos{ .pos = .{ @intCast(constants.world_width * ix), 0 } },
                ecs.component.Mov{
                    .velocity = Vec2.init(background_scroll[i], 0),
                },
            });
        }
    }
}

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    sim.meta.ticks_at_minigame_start = sim.meta.ticks_elapsed;
    _ = try spawnBackground(&sim.world);
    //TODO Change so it spawns one player for all current active players
    for (0..constants.max_player_count) |id| {
        // if (inputs[id].is_connected) {
        try spawnPlayer(&sim.world, @intCast(id));
        // }
    }
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{ .count = 0 }});
    try crown.init(sim, .{ 0, -10 });
}
pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    try jetpackSystem(&sim.world, inputs.latest());

    var collisions = collision.CollisionQueue.init(invar.arena) catch @panic("could not initialize collision queue");

    movement.update(&sim.world, &collisions, invar.arena) catch @panic("movement system failed");

    try collisionSystem(&sim.world);

    try pushSystem(&sim.world, &collisions);

    try spawnSystem(&sim.world, sim.meta.ticks_elapsed - sim.meta.ticks_at_minigame_start);

    try deathSystem(sim, &collisions);

    try scrollSystem(&sim.world);

    animator.update(&sim.world);
    try crown.update(sim);
    var query = sim.world.query(&.{ecs.component.Ctr}, &.{});
    while (query.next()) |_| {
        const ctr = try query.get(ecs.component.Ctr);
        if (ctr.count == constants.max_player_count) {
            sim.meta.minigame_id = 3;
        }
    }
}

/// Scroll background
fn scrollSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Pos}, &.{ecs.component.Col});
    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        if (pos.pos[0] + constants.world_width <= 4) { // +4 to hide visible seams
            pos.pos[0] = constants.world_width;
        }
    }
}

fn collisionSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Col, ecs.component.Pos, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const mov = try query.get(ecs.component.Mov);
        const col = try query.get(ecs.component.Col);
        if (pos.pos[1] < 0) {
            mov.velocity.vector[1] = 0;
            pos.pos[1] = 0;
        } else if (pos.pos[1] + col.dim[1] > constants.world_height) {
            mov.velocity.vector[1] = 0;
            pos.pos[1] = constants.world_height - col.dim[1];
        }
    }
}

fn pushSystem(world: *ecs.world.World, _: *collision.CollisionQueue) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Col, ecs.component.Pos, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        var pos = try query.get(ecs.component.Pos);
        const col = try query.get(ecs.component.Col);
        var obst_query = world.query(&.{ ecs.component.Col, ecs.component.Pos, ecs.component.Mov }, &.{ecs.component.Plr});
        while (obst_query.next()) |_| {
            const obst_pos = try obst_query.get(ecs.component.Pos);
            const obst_col = try obst_query.get(ecs.component.Col);
            const obst_mov = try obst_query.get(ecs.component.Mov);
            if (collision.intersectsAt(pos, col, obst_pos, obst_col, [_]i32{ 1, 0 })) {
                pos.pos[0] += obst_mov.velocity.x().toInt();
            }
        }
    }
}

fn jetpackSystem(world: *ecs.world.World, inputs: input.AllPlayerButtons) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const mov = try query.get(ecs.component.Mov);
        const state = inputs[plr.id];
        if (state.is_connected()) {
            if (state.vertical() > 0) {
                mov.velocity = mov.velocity.add(player_boost);
            }
        }
    }
}

fn deathSystem(sim: *simulation.Simulation, _: *collision.CollisionQueue) !void {
    var query = sim.world.query(&.{ ecs.component.Pos, ecs.component.Col }, &.{});
    while (query.next()) |entity| {
        const col = try query.get(ecs.component.Col);
        const pos = try query.get(ecs.component.Pos);

        const right = pos.pos[0] + col.dim[0];
        if (right < 0) {
            if (sim.world.checkSignature(entity, &.{ecs.component.Plr}, &.{})) {
                const plr = try sim.world.inspect(entity, ecs.component.Plr);
                var query_ctr = sim.world.query(&.{ecs.component.Ctr}, &.{});
                while (query_ctr.next()) |_| {
                    var ctr = try query_ctr.get(ecs.component.Ctr);
                    sim.meta.minigame_placements[plr.id] = constants.max_player_count - 1 - @as(u32, @intCast(ctr.count));
                    ctr.count += 1;
                }
            }
            sim.world.kill(entity);
            std.debug.print("entity {} died\n", .{entity.identifier});
        }
    }
}

fn spawnSystem(world: *ecs.world.World, ticks: u64) !void {
    if (ticks % @max(20, (80 -| (ticks / 160))) == 0) {
        spawnRandomObstacle(world);
    }

    if (ticks % @max(10, (60 -| (ticks / 120))) == 0) {
        spawnHorizontalObstacle(world);
    }
}

fn spawnVerticalObstacleUpper(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true, .pushing = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = vertical_obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
    }) catch unreachable;
}

fn spawnVerticalObstacleLower(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, constants.world_height - @as(i32, @intCast(length)) * constants.asset_resolution } },
        ecs.component.Col{
            .dim = .{ constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = vertical_obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
    }) catch unreachable;
}

fn spawnVerticalObstacleBoth(world: *ecs.world.World, delta: i32) void {
    spawnVerticalObstacleUpper(world, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
    spawnVerticalObstacleLower(world, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
}

pub fn spawnRandomObstacle(world: *ecs.world.World) void {
    const kind = std.Random.enumValue(rand, ObstacleKind);
    switch (kind) {
        ObstacleKind.ObstacleLower => {
            const length = std.Random.intRangeAtMost(rand, u32, 7, constants.world_height_tiles - 5);
            spawnVerticalObstacleLower(world, length);
        },
        ObstacleKind.ObstacleUpper => {
            const length = std.Random.intRangeAtMost(rand, u32, 7, constants.world_height_tiles - 5);
            spawnVerticalObstacleUpper(world, length);
        },
        ObstacleKind.ObstacleBoth => {
            const delta = std.Random.intRangeAtMost(rand, i32, 4, 8);
            spawnVerticalObstacleBoth(world, delta);
        },
    }
}

fn spawnHorizontalObstacle(world: *ecs.world.World) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{
                constants.world_width,
                std.Random.intRangeLessThan(rand, i32, 0, constants.world_height),
            },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .u = 0,
            .v = 0,
            .w = 3,
            .h = 1,
        },
        ecs.component.Mov{
            .velocity = horizontal_obstacle_velocity,
        },
        ecs.component.Col{
            .dim = .{ 3 * constants.asset_resolution, constants.asset_resolution },
            .layer = .{ .base = true, .pushing = true },
            .mask = .{ .base = false, .player = true },
        },
    }) catch unreachable;
}

fn spawnPlayer(world: *ecs.world.World, id: u32) !void {
    _ = try world.spawnWith(.{
        ecs.component.Plr{ .id = @intCast(id) },
        ecs.component.Pos{ .pos = .{ std.Random.intRangeAtMost(rand, i32, 64, 112), @divTrunc(constants.world_height, 2) } },
        ecs.component.Mov{
            .acceleration = player_gravity,
        },
        ecs.component.Col{
            .dim = .{ 12, 10 },
            .layer = collision.Layer{ .base = false, .player = true },
            .mask = collision.Layer{ .base = false, .player = false, .pushing = true },
        },
        ecs.component.Tex{
            .w = 2,
            .h = 1,
            .subpos = .{ -18, -6 },
            .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
            .tint = constants.player_colors[id],
        },
        ecs.component.Anm{ .animation = Animation.SmashRun, .interval = 8, .looping = true },
        // ecs.component.Dbg{},
    });
}
