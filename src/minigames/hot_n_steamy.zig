const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const timer = @import("../timer.zig");
const Vec2 = ecs.component.Vec2;
const F32 = ecs.component.F32;

var prng = std.rand.DefaultPrng.init(555);
const rand = prng.random();

const obstacle_height_base = 7;
const obstacle_height_delta = 6;

const player_gravity = Vec2.init(0, F32.init(1, 10));
const player_boost = Vec2.init(0, F32.init(-1, 4));
const obstacle_velocity = Vec2.init(-8, 0);
const obstacle_lifetime: usize = 200; // ticks until despawning obstacles, increase if they die too early
const obstacle_spawn_delay_initial: usize = 120;
const obstacle_spawn_delay_min: usize = 10;
const obstacle_spawn_delay_delta: usize = 5;

const ObstacleKind = enum { ObstacleUpper, ObstacleLower, ObstacleBoth };

fn spawnVerticalObstacleUpper(world: *ecs.world.World, _: ecs.entity.Entity, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
    }) catch unreachable;
}

fn spawnVerticalObstacleLower(world: *ecs.world.World, _: ecs.entity.Entity, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, constants.world_height - @as(i32, @intCast(length)) * constants.asset_resolution } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
    }) catch unreachable;
}

fn spawnVerticalObstacleBoth(world: *ecs.world.World, entity: ecs.entity.Entity, delta: i32) void {
    spawnVerticalObstacleUpper(world, entity, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
    spawnVerticalObstacleLower(world, entity, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
}

fn spawnRandomObstacle(world: *ecs.world.World, entity: ecs.entity.Entity) void {
    const kind = std.Random.enumValue(rand, ObstacleKind);
    switch (kind) {
        ObstacleKind.ObstacleLower => {
            const length = std.Random.intRangeAtMost(rand, u32, 1, constants.world_height_tiles - 1);
            spawnVerticalObstacleLower(world, entity, length);
        },
        ObstacleKind.ObstacleUpper => {
            const length = std.Random.intRangeAtMost(rand, u32, 1, constants.world_height_tiles - 1);
            spawnVerticalObstacleUpper(world, entity, length);
        },
        ObstacleKind.ObstacleBoth => {
            const delta = std.Random.intRangeAtMost(rand, i32, 1, 8);
            spawnVerticalObstacleBoth(world, entity, delta);
        },
    }
}

fn spawnHorizontalObstacle(world: *ecs.world.World, _: ecs.entity.Entity) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{
                constants.world_width,
                rl.getRandomValue(0, constants.world_height), // is this ok?
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
            .velocity = obstacle_velocity,
        },
        ecs.component.Col{
            .dim = .{ 48, 16 },
            .layer = .{ .base = true, .killing = true },
            .mask = .{ .base = true, .player = true },
        },
        ecs.component.Tmr{
            .action = ecs.world.World.kill,
            .delay = obstacle_lifetime,
        },
    }) catch unreachable;
}

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Tmr{
            .action = spawnRandomObstacle,
            .delay = obstacle_spawn_delay_initial,
            .repeat = true,
        },
    });

    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id },
            ecs.component.Pos{ .pos = .{ 8, 0 } },
            ecs.component.Mov{
                .acceleration = player_gravity,
            },
            //Somas lösning
            ecs.component.Col{
                .dim = .{ 16, 16 },
                .layer = collision.Layer{ .base = false, .player = true },
                .mask = collision.Layer{ .base = false, .player = false },
            },
            //Elliots lösning
            // ecs.component.Col{
            //     .dim = .{ 16, 16 },
            //     .layer = .{ .base = true, .player = true },
            //     .mask = .{
            //         .base = false,
            //         .killing = true,
            //     },
            // },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisFly, .interval = 8, .looping = true },
        });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    try jetpackSystem(&sim.world, inputs);
    var collisions = collision.CollisionQueue.init(arena) catch @panic("could not initialize collision queue");
    movement.update(&sim.world, &collisions, arena) catch @panic("movement system failed");
    //Somas lösning
    // if (sim.meta.ticks_elapsed % (80 - (sim.meta.ticks_elapsed / 80)) == 0) {
    //     try obsticleGenerator(&sim.world, std.Random.intRangeAtMost(rand, i32, -6, 6));
    // }
    // sim.meta.ticks_elapsed += 1;
    // try deathSystemS(&sim.world);
    // animator.update(&sim.world);

    // fn gravitySystem(world: *ecs.world.World) !void {
    //     var query = world.query(&.{ecs.component.Mov}, &.{});
    //     while (query.next()) |_| {
    //         const mov = try query.get(ecs.component.Mov);
    //         mov.acceleration = mov.acceleration.add(gravity);
    //     }
    // }
    //Elliots lösning
    try deathSystem(&sim.world, &collisions);
    // try spawnSystem(&sim.world);
    animator.update(&sim.world);
    timer.update(&sim.world);
}

fn jetpackSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const mov = try query.get(ecs.component.Mov);
        const state = inputs[plr.id];
        if (state.is_connected) {
            if (state.button_up.is_down) {
                mov.velocity = mov.velocity.add(player_boost);
            }
        }
    }
}

//Somas lösning
// fn obsticleGenerator(world: *ecs.world.World, length: i32) !void {
//     _ = try world.spawnWith(.{
//         ecs.component.Pos{ .pos = [_]i32{ constants.world_width, constants.world_height - 16 * (obstacle_height_base + length) } },
//         ecs.component.Col{
//             .dim = [_]i32{ 16, 16 * (obstacle_height_base + length) },
//             .layer = collision.Layer{ .base = false, .player = false },
//             .mask = collision.Layer{ .base = false, .player = true },
//         },
//         ecs.component.Mov{ .velocity = object_acc },
//         ecs.component.Tex{
//             .texture_hash = AssetManager.pathHash("assets/error.png"),
//             .w = 1,
//             .h = @intCast(obstacle_height_base + length),
//         },
//     });
// }

fn deathSystem(world: *ecs.world.World, collisions: *collision.CollisionQueue) !void {
    for (collisions.collisions.keys()) |col| {
        // TODO: right now it is random whether the player or obstacle dies, so we have to kill both
        // i call it a feature :,)
        // maybe world.checkSignature (?) to see if it is a player?
        world.kill(col.a);
        world.kill(col.b);
        std.debug.print("entity {} died\n", .{col.b.identifier});
    }
}

// fn spawnSystem(world: *ecs.world.World) !void {
//     if (obstacle_spawn_timer >= obstacle_spawn_delay) {
//         obstacle_spawn_timer = 0;
//         obstacle_spawn_delay = @max(obstacle_spawn_delay - obstacle_spawn_delay_delta, obstacle_spawn_delay_min);
//         _ = try world.spawnWith(.{
//             ecs.component.Pos{
//                 .pos = .{
//                     constants.world_width,
//                     rl.getRandomValue(0, constants.world_height), // is this ok?
//                 },
//             },
//             ecs.component.Tex{
//                 .texture_hash = AssetManager.pathHash("assets/error.png"),
//                 .u = 0,
//                 .v = 0,
//                 .w = 3,
//                 .h = 1,
//             },
//             ecs.component.Mov{
//                 .velocity = obstacle_velocity,
//             },
//             ecs.component.Col{
//                 .dim = .{ 48, 16 },
//                 .layer = .{ .base = true, .killing = true },
//                 .mask = .{ .base = true, .player = true },
//             },
//             ecs.component.Tmr{
//                 .action = ecs.world.World.kill,
//                 .delay = obstacle_lifetime,
//             },
//         });
//     } else {
//         obstacle_spawn_timer += 1;
//     }
// }
