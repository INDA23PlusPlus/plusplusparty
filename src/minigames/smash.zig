const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const audio = @import("../audio.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const input = @import("../input.zig");
const Animation = @import("../animation/animations.zig").Animation;
const AssetManager = @import("../AssetManager.zig");
const AudioManager = @import("../AudioManager.zig");
const Invariables = @import("../Invariables.zig");

// TODO: Block particle
// TODO: Fix bug where players are not being push away when attacking very close

const left_texture_offset = [_]i32{ -5, -10 };
const right_texture_offset = [_]i32{ -21, -10 };

const redness_increase_frames = 30;
const pushback_bonus = ecs.component.F32.init(1, 1).mul(ecs.component.F32.init(1, 60));

const ground_speed = ecs.component.F32.init(4, 3);
const ground_acceleration = ecs.component.F32.init(1, 6);
const ground_deceleration = ecs.component.F32.init(1, 3);
const ground_friction = ecs.component.F32.init(1, 10);

const air_speed = ecs.component.F32.init(5, 3);
const air_acceleration = ecs.component.F32.init(1, 10);
const air_deceleration = ecs.component.F32.init(1, 10);
const air_friction = ecs.component.F32.init(1, 20);

const jump_strength = ecs.component.F32.init(-5, 2);
const jump_gravity = ecs.component.F32.init(1, 12);
const jump_buffer = 6;
const coyote_time = 8;

const fall_gravity = ecs.component.Vec2.init(0, ecs.component.F32.init(1, 4));
const fall_speed = ecs.component.Vec2.init(0, ecs.component.F32.init(4, 1));

const hitstun = 10;
const bounce_strength = ecs.component.F32.init(3, 2);

const attack_strength_small = ecs.component.F32.init(2, 1);
const attack_strength_medium = ecs.component.F32.init(7, 2);
const attack_strength_large = ecs.component.F32.init(9, 2);
const attack_cooldown = 24;
const attack_buffer = 5;
const attack_dimensions = [_]i32{ 16, 16 };
const attack_ticks = 7;
const attack_player_offset = [_]i32{ -5, -5 };
const attack_directional_offset = 16;
const attack_bounce = ecs.component.Vec2.init(-1, 1).mul(ecs.component.F32.init(1, 2));

const block_multiplier = ecs.component.F32.init(5, 4);
const block_cooldown = 32;
const block_buffer = 5;
const block_ticks = 7;
const block_dimensions = [_]i32{ 16, 16 };

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    sim.meta.minigame_counter = @intCast(timeline.connectedPlayerCount());

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_0.png"),
            .w = 32,
            .h = 18,
        },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ 346, 60 },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_sun.png"),
            .w = 4,
            .h = 4,
        },
        ecs.component.Anm{
            .animation = .SmashSun,
            .interval = 8,
        },
        ecs.component.Mov{
            .velocity = ecs.component.Vec2.init(
                0,
                ecs.component.F32.init(1, 60),
            ),
        },
        ecs.component.Tmr{
            .ticks = 100,
        },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_1.png"),
            .w = 32,
            .h = 18,
        },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ 0, 32 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_2.png"),
            .w = 32,
            .h = 18,
        },
    });

    // Platform
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16 * 6, 16 * 15 } },
        ecs.component.Col{
            .dim = [_]i32{ 16 * 20, 16 * 3 },
            .layer = collision.Layer{ .base = false, .platform = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_platform.png"),
            .w = 20,
            .h = 5,
            .subpos = .{ 0, -32 },
        },
    });

    var offset: i32 = 0;

    // Players
    for (timeline.latest(), 0..) |plr, i| {
        if (plr.dpad == .Disconnected) continue;

        const left: i32 = @intFromBool(i % 2 == 0);
        const side: i32 = 1 - 2 * left;
        offset += 16 * left;

        const id: u32 = @intCast(i);

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id },
            ecs.component.Pos{
                .pos = [_]i32{
                    (constants.world_width / 2) + side * offset - left * 6,
                    234,
                },
            },
            ecs.component.Col{
                .dim = [_]i32{ 6, 6 },
                .layer = collision.Layer{ .base = false, .player = true },
                .mask = collision.Layer{ .base = false, .platform = true, .player = true },
            },
            ecs.component.Mov{},
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                .w = 2,
                .subpos = if (i % 2 == 0) right_texture_offset else left_texture_offset,
                .flip_horizontal = i % 2 != 0,
                .tint = constants.player_colors[i],
            },
            ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 8, .looping = true },
            ecs.component.Tmr{}, // Coyote timer
            ecs.component.Ctr{}, // Attack timer, block timer, and hit recovery timer
        });

        sim.meta.minigame_placements[id] = 0; // Everyone's a winner by default
    }

    // Crown
    try @import("../crown.zig").init(sim, .{ -5, -22 });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, rt: Invariables) !void {
    if (sim.meta.minigame_counter <= 1) sim.meta.minigame_id = constants.minigame_scoreboard;

    sim.meta.minigame_timer = @min(60, sim.meta.minigame_timer + @intFromBool(sim.meta.ticks_elapsed % 60 == 0));

    audio.update(&sim.world);

    try actionSystem(sim, timeline); // 50 laps/ms (2 players)

    blockSystem(sim);
    attackSystem(sim);
    hitSystem(&sim.world);

    const inputs = &timeline.latest();
    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    gravitySystem(&sim.world); // 150 laps/ms
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement"); // 70 laps/ms
    try resolveCollisions(&sim.world, &collisions); // 400 laps/ms
    airborneSystem(&sim.world); // 70 laps/ms
    forceSystem(&sim.world, inputs); // 120 laps/ms

    try deathSystem(sim, inputs); // 200 laps/ms

    animationSystem(&sim.world, inputs); // 150 laps/ms
    animator.update(&sim.world); // 160 laps/ms
    particleSystem(&sim.world); // 250 laps/ms
    backgroundColorSystem(sim); // 650 laps/ms

    try @import("../crown.zig").update(sim);

    var dead_entities = sim.world.query(&.{}, ecs.component.components);

    while (dead_entities.next()) |entity| {
        sim.world.kill(entity);
    }
}

fn actionSystem(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    var query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Tmr,
        ecs.component.Ctr,
    }, &.{});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const tmr = query.get(ecs.component.Tmr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;

        const state = timeline.latest()[plr.id];

        const grounded = sim.world.checkSignature(entity, &.{}, &.{ecs.component.Air});
        const not_jumping = sim.world.checkSignature(entity, &.{}, &.{ecs.component.Jmp});
        const wants_jump = state.button_a == .Pressed or (if (timeline.buttonStateTick(plr.id, .a, .Pressed)) |press_tick| sim.meta.ticks_elapsed - press_tick < jump_buffer else false);
        const can_jump = not_jumping and (grounded or tmr.ticks < coyote_time);

        if (wants_jump and can_jump) {
            mov.velocity.vector[1] = jump_strength.bits;
            sim.world.promote(entity, &.{ecs.component.Jmp});
            tmr.ticks = coyote_time;

            _ = try sim.world.spawnWith(.{
                pos.*,
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_jump_smoke.png"),
                    .subpos = [_]i32{ -14, -26 },
                    .w = 2,
                    .h = 2,
                    .tint = rl.Color.init(100, 100, 100, 100),
                },
                ecs.component.Tmr{},
                ecs.component.Anm{ .interval = 8, .animation = .SmashJumpSmoke },
                ecs.component.Jmp{},
                ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/jump.wav") },
            });
        }

        if ((!state.button_a.is_down() or mov.velocity.vector[1] > 0) and sim.world.checkSignature(entity, &.{ecs.component.Jmp}, &.{})) {
            sim.world.demote(entity, &.{ecs.component.Jmp});
        }

        const b_press_tick = timeline.buttonStateTick(plr.id, .b, .Pressed);

        const wants_block = state.dpad == .None and (state.button_b == .Pressed or (if (b_press_tick) |press_tick| sim.meta.ticks_elapsed - press_tick < block_buffer else false));
        const can_block = (if (b_press_tick) |press_tick| sim.meta.ticks_elapsed - press_tick < attack_cooldown else false) and ctr.count < block_cooldown and sim.world.checkSignature(entity, &.{}, &.{ ecs.component.Atk, ecs.component.Blk, ecs.component.Hit });

        if (wants_block and can_block) {
            sim.world.promote(entity, &.{ecs.component.Blk});

            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = pos.pos + [_]i32{ -5, -5 } },
                ecs.component.Col{
                    .dim = [_]i32{ 16, 16 },
                    .layer = collision.Layer{ .base = false, .pushing = true },
                    .mask = collision.Layer{ .base = false },
                },
                ecs.component.Tex{
                    .subpos = [_]i32{ -8, -8 },
                    .texture_hash = AssetManager.pathHash("assets/smash_attack_smoke.png"), // TODO: Block texture
                    .w = 2,
                    .h = 2,
                    .tint = rl.Color.init(100, 100, 100, 100),
                },
                ecs.component.Anm{ .interval = 8, .animation = .SmashAttackSmoke }, // TODO: Block animation
                ecs.component.Ctr{},
                ecs.component.Blk{},
                ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/block.wav") },
            });

            continue;
        }

        const wants_attack = state.dpad != .None and (state.button_b == .Pressed or (if (b_press_tick) |press_tick| sim.meta.ticks_elapsed - press_tick < attack_buffer else false));
        const can_attack = (if (b_press_tick) |press_tick| sim.meta.ticks_elapsed - press_tick < attack_cooldown else false) and ctr.count < attack_cooldown and sim.world.checkSignature(entity, &.{}, &.{ ecs.component.Atk, ecs.component.Blk, ecs.component.Hit });

        if (wants_attack and can_attack) {
            sim.world.promote(entity, &.{ecs.component.Atk});

            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = pos.pos + attack_player_offset + switch (state.dpad) {
                    .North => @Vector(2, i32){ 0, -attack_directional_offset },
                    .South => @Vector(2, i32){ 0, attack_directional_offset },
                    .West => @Vector(2, i32){ -attack_directional_offset, 0 },
                    .East => @Vector(2, i32){ attack_directional_offset, 0 },
                    .NorthWest => @Vector(2, i32){ -attack_directional_offset, -attack_directional_offset },
                    .NorthEast => @Vector(2, i32){ attack_directional_offset, -attack_directional_offset },
                    .SouthWest => @Vector(2, i32){ -attack_directional_offset, attack_directional_offset },
                    .SouthEast => @Vector(2, i32){ attack_directional_offset, attack_directional_offset },
                    else => @Vector(2, i32){ 0, 0 },
                } },
                ecs.component.Ctr{},
                ecs.component.Dir{ .facing = switch (state.dpad) {
                    .North => .North,
                    .South => .South,
                    .West => .West,
                    .East => .East,
                    .NorthWest => .Northwest,
                    .NorthEast => .Northeast,
                    .SouthWest => .Southwest,
                    .SouthEast => .Southeast,
                    else => .None,
                } },
                ecs.component.Col{
                    .dim = attack_dimensions,
                    .layer = collision.Layer{ .base = false, .damaging = true },
                    .mask = collision.Layer{ .base = false },
                },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_attack_smoke.png"),
                    .subpos = [_]i32{ -8, -8 },
                    .w = 2,
                    .h = 2,
                    .tint = rl.Color.init(100, 100, 100, 100),
                },
                ecs.component.Anm{ .interval = 8, .animation = .SmashAttackSmoke },
                ecs.component.Lnk{ .child = entity },
                ecs.component.Atk{},
                ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/attack.wav") },
            });
        }
    }
}

fn blockSystem(sim: *simulation.Simulation) void {
    var blocker_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Blk,
    }, &.{
        ecs.component.Atk,
        ecs.component.Hit,
    });

    while (blocker_query.next()) |entity| {
        const ctr = blocker_query.get(ecs.component.Ctr) catch unreachable;

        if (ctr.count >= block_cooldown) {
            sim.world.demote(entity, &.{ecs.component.Blk});
            ctr.count = 0;
        } else {
            ctr.count += 1;
        }
    }

    var block_query = sim.world.query(&.{
        ecs.component.Ctr,
        ecs.component.Blk,
    }, &.{
        ecs.component.Plr,
    });

    while (block_query.next()) |entity| {
        const ctr = block_query.get(ecs.component.Ctr) catch unreachable;

        if (ctr.count >= 40) { // TODO: Match particle animation length
            sim.world.kill(entity);
        } else {
            ctr.count += 1;
        }
    }

    var block_hitbox_query = sim.world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Ctr,
        ecs.component.Blk,
    }, &.{
        ecs.component.Plr,
    });

    while (block_hitbox_query.next()) |entity| {
        const blk_ctr = block_hitbox_query.get(ecs.component.Ctr) catch unreachable;

        if (blk_ctr.count >= block_ticks) {
            sim.world.demote(entity, &.{ecs.component.Col});
            continue;
        }

        const blk_pos = block_hitbox_query.get(ecs.component.Pos) catch unreachable;
        const blk_col = block_hitbox_query.get(ecs.component.Col) catch unreachable;

        var attack_query = sim.world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
            ecs.component.Dir,
            ecs.component.Atk,
            ecs.component.Lnk,
        }, &.{
            ecs.component.Plr,
        });

        while (attack_query.next()) |atk| {
            const atk_pos = attack_query.get(ecs.component.Pos) catch unreachable;
            const atk_col = attack_query.get(ecs.component.Col) catch unreachable;

            if (!collision.intersects(blk_pos, blk_col, atk_pos, atk_col)) continue;

            const atk_dir = attack_query.get(ecs.component.Dir) catch unreachable;
            const atk_lnk = attack_query.get(ecs.component.Lnk) catch unreachable;

            const plr = atk_lnk.child orelse continue;
            if (!sim.world.checkSignature(plr, &.{ ecs.component.Plr, ecs.component.Mov, ecs.component.Ctr }, &.{ecs.component.Hit})) continue;

            const mov = sim.world.inspect(plr, ecs.component.Mov) catch unreachable;
            const ctr = sim.world.inspect(plr, ecs.component.Ctr) catch unreachable;

            const multiplier = pushback_bonus.mul(@as(i16, @intCast(sim.meta.minigame_timer))).add(1);
            const small_push = attack_strength_small.mul(block_multiplier).mul(multiplier);
            const medium_push = attack_strength_medium.mul(block_multiplier).mul(multiplier);
            const large_push = attack_strength_large.mul(block_multiplier).mul(multiplier);

            mov.velocity = switch (atk_dir.facing) {
                .None => ecs.component.Vec2.init(0, 0),
                .North => ecs.component.Vec2.init(0, medium_push),
                .South => ecs.component.Vec2.init(0, large_push.mul(-1)),
                .West => ecs.component.Vec2.init(large_push, small_push.mul(-1)),
                .East => ecs.component.Vec2.init(large_push.mul(-1), small_push.mul(-1)),
                .Northwest => ecs.component.Vec2.init(medium_push, medium_push),
                .Northeast => ecs.component.Vec2.init(medium_push.mul(-1), medium_push),
                .Southwest => ecs.component.Vec2.init(medium_push, medium_push.mul(-1)),
                .Southeast => ecs.component.Vec2.init(medium_push.mul(-1), medium_push.mul(-1)),
            };

            sim.world.promote(plr, &.{ecs.component.Hit});
            ctr.count = 0;

            sim.world.demote(atk, &.{ecs.component.Col});
        }
    }
}

fn attackSystem(sim: *simulation.Simulation) void {
    var attacker_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Atk,
    }, &.{
        ecs.component.Blk,
        ecs.component.Hit,
    });

    while (attacker_query.next()) |entity| {
        const ctr = attacker_query.get(ecs.component.Ctr) catch unreachable;

        if (ctr.count >= attack_cooldown) {
            sim.world.demote(entity, &.{ecs.component.Atk});
            ctr.count = 0;
        } else {
            ctr.count += 1;
        }
    }

    var attack_query = sim.world.query(&.{
        ecs.component.Ctr,
        ecs.component.Atk,
    }, &.{
        ecs.component.Plr,
    });

    while (attack_query.next()) |entity| {
        const ctr = attack_query.get(ecs.component.Ctr) catch unreachable;

        if (ctr.count >= 40) {
            sim.world.kill(entity);
        } else {
            ctr.count += 1;
        }
    }

    var attack_hitbox_query = sim.world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Dir,
        ecs.component.Ctr,
        ecs.component.Lnk,
        ecs.component.Atk,
    }, &.{
        ecs.component.Plr,
    });

    while (attack_hitbox_query.next()) |entity| {
        const atk_ctr = attack_hitbox_query.get(ecs.component.Ctr) catch unreachable;

        if (atk_ctr.count >= attack_ticks) {
            sim.world.demote(entity, &.{ecs.component.Col});
            continue;
        }

        const atk_lnk = attack_hitbox_query.get(ecs.component.Lnk) catch unreachable;
        const atk_pos = attack_hitbox_query.get(ecs.component.Pos) catch unreachable;
        const atk_col = attack_hitbox_query.get(ecs.component.Col) catch unreachable;
        const atk_dir = attack_hitbox_query.get(ecs.component.Dir) catch unreachable;

        var player_query = sim.world.query(&.{
            ecs.component.Plr,
            ecs.component.Pos,
            ecs.component.Col,
            ecs.component.Mov,
            ecs.component.Ctr,
        }, &.{
            ecs.component.Hit,
        });

        while (player_query.next()) |plr| {
            if ((atk_lnk.child orelse continue).eq(plr)) continue;

            const plr_pos = player_query.get(ecs.component.Pos) catch unreachable;
            const plr_col = player_query.get(ecs.component.Col) catch unreachable;

            if (!collision.intersects(atk_pos, atk_col, plr_pos, plr_col)) continue;

            const plr_mov = player_query.get(ecs.component.Mov) catch unreachable;
            const plr_ctr = player_query.get(ecs.component.Ctr) catch unreachable;

            const multiplier = pushback_bonus.mul(@as(i16, @intCast(sim.meta.minigame_timer))).add(1);
            const small_push = attack_strength_small.mul(multiplier);
            const medium_push = attack_strength_medium.mul(multiplier);
            const large_push = attack_strength_large.mul(multiplier);

            plr_mov.velocity = switch (atk_dir.facing) {
                .None => ecs.component.Vec2.init(0, 0),
                .North => ecs.component.Vec2.init(0, medium_push.mul(-1)),
                .South => ecs.component.Vec2.init(0, large_push),
                .West => ecs.component.Vec2.init(large_push.mul(-1), small_push.mul(-1)),
                .East => ecs.component.Vec2.init(large_push, small_push.mul(-1)),
                .Northwest => ecs.component.Vec2.init(medium_push.mul(-1), medium_push.mul(-1)),
                .Northeast => ecs.component.Vec2.init(medium_push, medium_push.mul(-1)),
                .Southwest => ecs.component.Vec2.init(medium_push.mul(-1), medium_push),
                .Southeast => ecs.component.Vec2.init(medium_push, medium_push),
            };

            sim.world.promote(plr, &.{ecs.component.Hit});
            sim.world.promoteWith(plr, .{ecs.component.Snd{
                .sound_hash = comptime AudioManager.path_to_key("assets/audio/hit.wav"),
            }});
            plr_ctr.count = 0;
        }
    }
}

fn hitSystem(world: *ecs.world.World) void {
    var hit_query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Hit,
    }, &.{});

    while (hit_query.next()) |entity| {
        const ctr = hit_query.get(ecs.component.Ctr) catch unreachable;

        if (ctr.count >= hitstun) {
            world.demote(entity, &.{ecs.component.Hit});
            ctr.count = 0;
        } else {
            ctr.count += 1;
        }
    }
}

fn deathSystem(sim: *simulation.Simulation, inputs: *const input.AllPlayerButtons) !void {
    var query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Col,
        ecs.component.Tex,
        ecs.component.Anm,
        ecs.component.Ctr,
        ecs.component.Tmr,
    }, &.{});

    var dead_players: u32 = 0;

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;

        const x = pos.pos[0];
        const y = pos.pos[1];

        if (x < 0 or constants.world_width < x or y < 0 or constants.world_height < y) {
            dead_players += 1;
            sim.meta.minigame_counter -= 1;

            const position = @min(@max(pos.pos, @Vector(2, i32){ 0, 0 }), @Vector(2, i32){ constants.world_width, constants.world_height });
            const rotational_offset = if (constants.world_width < x) [_]i32{ -28, 20 } else if (y < 0) [_]i32{ 16, 32 } else if (x < 0) [_]i32{ 28, -20 } else [_]i32{ -12, -32 };

            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = position + rotational_offset },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_death.png"),
                    .w = 2,
                    .h = 2,
                    .rotate = if (constants.world_width < x) .R270 else if (y < 0) .R180 else if (x < 0) .R90 else .R0,
                },
                ecs.component.Anm{ .animation = .SmashDeath, .interval = 4 },
                ecs.component.Tmr{},
                ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/death.wav") },
            });

            sim.world.demote(entity, &.{
                ecs.component.Pos,
                ecs.component.Mov,
                ecs.component.Col,
                ecs.component.Tex,
                ecs.component.Anm,
                ecs.component.Ctr,
                ecs.component.Tmr,
            });
        } else if (inputs[plr.id].dpad == .Disconnected) {
            dead_players += 1;
            sim.meta.minigame_counter -= 1;

            // Poof
            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = pos.pos + [_]i32{ -5, -5 } },
                ecs.component.Tex{
                    .subpos = [_]i32{ -8, -8 },
                    .texture_hash = AssetManager.pathHash("assets/smash_attack_smoke.png"),
                    .w = 2,
                    .h = 2,
                    .tint = rl.Color.init(100, 100, 100, 100),
                },
                ecs.component.Anm{ .interval = 8, .animation = .SmashAttackSmoke },
            });

            sim.world.demote(entity, &.{
                ecs.component.Pos,
                ecs.component.Mov,
                ecs.component.Col,
                ecs.component.Tex,
                ecs.component.Anm,
                ecs.component.Ctr,
                ecs.component.Tmr,
            });
        }
    }

    var dead_player_query = sim.world.query(&.{
        ecs.component.Plr,
    }, &.{
        ecs.component.Mov,
        ecs.component.Col,
        ecs.component.Tex,
        ecs.component.Anm,
        ecs.component.Ctr,
        ecs.component.Tmr,
    });

    while (dead_player_query.next()) |entity| {
        const plr = dead_player_query.get(ecs.component.Plr) catch unreachable;

        sim.meta.minigame_placements[plr.id] = sim.meta.minigame_counter + dead_players - 1;
        sim.world.kill(entity);
    }
}

fn forceSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) void {
    var query_grounded = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
    }, &.{
        ecs.component.Air,
        ecs.component.Hit,
    });

    while (query_grounded.next()) |_| {
        const plr = query_grounded.get(ecs.component.Plr) catch unreachable;
        const mov = query_grounded.get(ecs.component.Mov) catch unreachable;

        const target = switch (inputs[plr.id].dpad) {
            .NorthWest, .SouthWest, .West => ground_speed.mul(-1),
            .NorthEast, .SouthEast, .East => ground_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) ground_acceleration else ground_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (mov.velocity.x().abs().cmp(ground_friction, .lt)) mov.velocity.vector[0] = 0;
    }

    var query_airborne = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Air,
    }, &.{
        ecs.component.Hit,
    });

    while (query_airborne.next()) |_| {
        const plr = query_airborne.get(ecs.component.Plr) catch unreachable;
        const mov = query_airborne.get(ecs.component.Mov) catch unreachable;

        const target = switch (inputs[plr.id].dpad) {
            .NorthWest, .SouthWest, .West => air_speed.mul(-1),
            .NorthEast, .SouthEast, .East => air_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) air_acceleration else air_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (mov.velocity.x().abs().cmp(air_friction, .lt)) mov.velocity.vector[0] = 0;
    }
}

fn gravitySystem(world: *ecs.world.World) void {
    var query_jumping = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
        ecs.component.Jmp,
    }, &.{
        ecs.component.Hit,
    });

    while (query_jumping.next()) |_| {
        const mov = query_jumping.get(ecs.component.Mov) catch unreachable;

        mov.velocity.vector[1] += jump_gravity.bits;
    }

    var query_falling = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
    }, &.{
        ecs.component.Jmp,
        ecs.component.Hit,
    });

    while (query_falling.next()) |_| {
        const mov = query_falling.get(ecs.component.Mov) catch unreachable;

        mov.velocity = mov.velocity.add(fall_gravity);

        mov.velocity.vector[1] = @min(fall_speed.vector[1], mov.velocity.vector[1]);
    }
}

fn airborneSystem(world: *ecs.world.World) void {
    var query_airborne = world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Col,
        ecs.component.Air,
        ecs.component.Tmr,
    }, &.{});

    while (query_airborne.next()) |ent1| {
        const tmr1 = query_airborne.get(ecs.component.Tmr) catch unreachable;

        tmr1.ticks += 1;

        var query = world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        while (query.next()) |ent2| {
            if (ent1.eq(ent2)) continue;

            const pos1 = query_airborne.get(ecs.component.Pos) catch unreachable;
            const col1 = query_airborne.get(ecs.component.Col) catch unreachable;
            const pos2 = query.get(ecs.component.Pos) catch unreachable;
            const col2 = query.get(ecs.component.Col) catch unreachable;

            if (!(col1.layer.intersects(col2.mask) or col1.mask.intersects(col2.layer))) {
                continue;
            }

            if (world.checkSignature(ent2, &.{}, &.{ecs.component.Plr}) and collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                if (tmr1.ticks < 8 and world.checkSignature(ent1, &.{}, &.{ecs.component.Jmp})) {
                    world.promote(ent1, &.{ecs.component.Jmp});
                    const mov1 = query_airborne.get(ecs.component.Mov) catch unreachable;
                    mov1.velocity.vector[1] = jump_strength.bits;
                } else {
                    world.demote(ent1, &.{ecs.component.Air});
                    tmr1.ticks = 0;
                }
                break;
            }
        }
    }

    var query_grounded = world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Col,
    }, &.{
        ecs.component.Air,
    });

    while (query_grounded.next()) |ent1| {
        const mov1 = query_grounded.get(ecs.component.Mov) catch unreachable;

        if (mov1.velocity.vector[1] > 0) mov1.velocity.vector[1] = 0;

        var query = world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        var airborne = true;

        while (query.next()) |ent2| {
            if (ent1.eq(ent2)) continue;

            const pos1 = query_grounded.get(ecs.component.Pos) catch unreachable;
            const col1 = query_grounded.get(ecs.component.Col) catch unreachable;
            const pos2 = query.get(ecs.component.Pos) catch unreachable;
            const col2 = query.get(ecs.component.Col) catch unreachable;

            if (!(col1.layer.intersects(col2.mask) or col1.mask.intersects(col2.layer))) {
                continue;
            }

            if (collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                airborne = false;
                break;
            }
        }

        if (airborne) world.promote(ent1, &.{ecs.component.Air});
    }
}

fn resolveCollisions(world: *ecs.world.World, collisions: *collision.CollisionQueue) !void {
    for (collisions.data.keys()) |c| {
        const ent1 = c.a;
        const ent2 = c.b;

        const hit1 = world.checkSignature(ent1, &.{ecs.component.Hit}, &.{});
        const hit2 = world.checkSignature(ent2, &.{ecs.component.Hit}, &.{});
        const plr1 = world.checkSignature(ent1, &.{ ecs.component.Plr, ecs.component.Pos, ecs.component.Col, ecs.component.Mov }, &.{});
        const plr2 = world.checkSignature(ent2, &.{ ecs.component.Plr, ecs.component.Pos, ecs.component.Col, ecs.component.Mov }, &.{});

        if (plr1 and plr2) {
            const pos1 = world.inspect(ent1, ecs.component.Pos) catch unreachable;
            const pos2 = world.inspect(ent2, ecs.component.Pos) catch unreachable;
            const mov1 = world.inspect(ent1, ecs.component.Mov) catch unreachable;
            const mov2 = world.inspect(ent2, ecs.component.Mov) catch unreachable;

            if (hit1 or hit2) {
                const tmp = mov1.velocity;
                mov1.velocity = mov2.velocity;
                mov2.velocity = tmp;

                _ = try world.spawnWith(.{ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/bounce.wav") }});
            } else {
                const left: i16 = @intFromBool(pos1.pos[0] < pos2.pos[0]);
                const right: i16 = @intFromBool(pos1.pos[0] > pos2.pos[0]);
                const middle: i16 = @intFromBool(pos1.pos[0] == pos2.pos[0]);
                const top: i16 = @intFromBool(pos1.pos[1] < pos2.pos[1]);
                const bottom: i16 = @intFromBool(pos1.pos[1] > pos2.pos[1]);

                const direction = (right - left) + middle * (bottom - top);
                const bounce = bounce_strength.mul(direction);

                mov1.velocity.vector[0] += bounce.bits;
                mov2.velocity.vector[0] -= bounce.bits;
            }
        } else if (plr1 and hit1) {
            const pos1 = world.inspect(ent1, ecs.component.Pos) catch unreachable;
            const pos2 = world.inspect(ent2, ecs.component.Pos) catch unreachable;
            const col1 = world.inspect(ent1, ecs.component.Col) catch unreachable;
            const col2 = world.inspect(ent2, ecs.component.Col) catch unreachable;
            const mov1 = world.inspect(ent1, ecs.component.Mov) catch unreachable;

            if (collision.intersectsAt(pos1, col1, pos2, col2, .{ -1, 0 }) or collision.intersectsAt(pos1, col1, pos2, col2, .{ 1, 0 })) {
                mov1.velocity = mov1.velocity.mul(attack_bounce);
            } else {
                mov1.velocity = mov1.velocity.mul(attack_bounce.mul(-1));
            }

            _ = try world.spawnWith(.{ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/bounce.wav") }});
        } else if (plr2 and hit2) {
            const pos1 = world.inspect(ent1, ecs.component.Pos) catch unreachable;
            const pos2 = world.inspect(ent2, ecs.component.Pos) catch unreachable;
            const col1 = world.inspect(ent1, ecs.component.Col) catch unreachable;
            const col2 = world.inspect(ent2, ecs.component.Col) catch unreachable;
            const mov2 = world.inspect(ent2, ecs.component.Mov) catch unreachable;

            if (collision.intersectsAt(pos1, col1, pos2, col2, .{ -1, 0 }) or collision.intersectsAt(pos1, col1, pos2, col2, .{ 1, 0 })) {
                mov2.velocity = mov2.velocity.mul(attack_bounce);
            } else {
                mov2.velocity = mov2.velocity.mul(attack_bounce.mul(-1));
            }

            _ = try world.spawnWith(.{ecs.component.Snd{ .sound_hash = comptime AudioManager.path_to_key("assets/audio/bounce.wav") }});
        }
    }
}

// VISUALS

fn animationSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Tex,
        ecs.component.Anm,
    }, &.{});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const anm = query.get(ecs.component.Anm) catch unreachable;

        const state = inputs[plr.id];

        switch (state.dpad) {
            .East, .NorthEast, .SouthEast => if (mov.velocity.vector[0] > 0) {
                tex.flip_horizontal = false;
                tex.subpos = right_texture_offset;
            },
            .West, .NorthWest, .SouthWest => if (mov.velocity.vector[0] < 0) {
                tex.flip_horizontal = true;
                tex.subpos = left_texture_offset;
            },
            else => {},
        }

        const previous = anm.animation;

        const moving = mov.velocity.vector[0] != 0 and switch (state.dpad) {
            .None, .North, .South => false,
            else => true,
        };
        const jumping = world.checkSignature(entity, &.{ecs.component.Jmp}, &.{});
        const airborne = world.checkSignature(entity, &.{ecs.component.Air}, &.{});
        const rising = airborne and mov.velocity.vector[1] <= 0;
        const falling = airborne and mov.velocity.vector[1] > 0;
        const crouching = mov.velocity.vector[0] == 0 and mov.velocity.vector[1] == 0 and state.dpad == .South and !airborne;
        const attacking = world.checkSignature(entity, &.{ecs.component.Atk}, &.{});
        const blocking = world.checkSignature(entity, &.{ecs.component.Blk}, &.{});
        const hit = world.checkSignature(entity, &.{ecs.component.Hit}, &.{});

        if (moving) {
            anm.animation = .SmashRun;
        } else if (crouching) {
            anm.animation = .SmashCrouch;
        } else {
            anm.animation = .SmashIdle;
        }

        if (jumping) {
            anm.looping = false;
            anm.animation = .SmashJump;
        } else if (rising) {
            anm.looping = false;
            anm.animation = .SmashRise;
        } else if (falling) {
            anm.looping = false;
            anm.animation = .SmashFall;
        } else {
            anm.looping = true;
        }

        if (hit) {
            anm.animation = .SmashHit;
        } else if (attacking) {
            anm.animation = .SmashAttack;
        } else if (blocking) {
            anm.animation = .SmashBlock;
        }

        if (anm.animation != previous) anm.subframe = 0;
    }
}

fn backgroundColorSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % redness_increase_frames != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Tex,
    }, &.{
        ecs.component.Plr,
        ecs.component.Kng,
    });

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;

        tex.tint.b = @max(100, tex.tint.b - 1);
        tex.tint.g = @max(100, tex.tint.g - 1);
    }
}

fn particleSystem(world: *ecs.world.World) void {
    var jump_query = world.query(&.{
        ecs.component.Tmr,
        ecs.component.Pos,
        ecs.component.Tex,
        ecs.component.Anm,
        ecs.component.Jmp,
    }, &.{
        ecs.component.Col,
        ecs.component.Plr,
    });

    while (jump_query.next()) |entity| {
        const tmr = jump_query.get(ecs.component.Tmr) catch unreachable;

        if (tmr.ticks == 32) {
            world.kill(entity);
        } else {
            tmr.ticks += 1;
        }
    }

    var death_query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Tex,
        ecs.component.Anm,
        ecs.component.Tmr,
    }, &.{
        ecs.component.Col,
        ecs.component.Plr,
        ecs.component.Jmp,
    });

    while (death_query.next()) |entity| {
        const tmr = death_query.get(ecs.component.Tmr) catch unreachable;

        if (tmr.ticks == 20 or tmr.ticks == 70000) {
            world.kill(entity);
        } else {
            tmr.ticks += 1;
        }
    }
}
