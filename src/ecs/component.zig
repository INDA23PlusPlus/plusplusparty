const rl = @import("raylib");

const constants = @import("../constants.zig");

const Layer = @import("../physics/collision.zig").Layer;

const Entity = @import("entity.zig").Entity;
const World = @import("world.zig").World;

const entity_count = @import("world.zig").N;

pub const F32 = @import("../math/fixed.zig").F(16, 16);
pub const Vec2 = @import("../math/linear.zig").V(2, F32);
const Animation = @import("../animation/animations.zig").Animation;
const AssetManager = @import("../AssetManager.zig");

/// Components the ECS supports.
/// All components MUST be default initializable.
/// All components MUST have a documented purpose.
pub const components: []const type = &.{
    Plr,
    Pos,
    Mov,
    Col,
    Dir,
    Tex,
    Txt,
    Anm,
    Lnk,
    Ctr,
    Air,
    Jmp,
    Bnd,
    Uid,
};

/// Entities with this component are positionable.
pub const Pos = struct {
    pos: @Vector(2, i32) = .{ 0, 0 }, // x, y
};

/// Entities with this component are movable.
pub const Mov = struct {
    subpixel: Vec2 = Vec2{},
    velocity: Vec2 = Vec2{},
    acceleration: Vec2 = Vec2{},
};

/// Entities with this component are collidable.
pub const Col = struct {
    off: @Vector(2, i32) = .{ 0, 0 }, // x, y
    dim: @Vector(2, i32) = .{ 0, 0 }, // w, h
    layer: Layer = Layer{}, // Determines what entities collide with this entity.
    mask: Layer = Layer{}, // Determines what entities this entity collides with.
};

/// Entities with this component may be linked to other entities.
pub const Lnk = struct {
    child: ?Entity = null,
};

/// Entities with component can point in a direction.
pub const Dir = struct {
    facing: enum {
        None,
        North,
        South,
        West,
        East,
        Northwest,
        Northeast,
        Southwest,
        Southeast,
    } = .None,
};

/// Entities with this component are player controllable.
pub const Plr = struct {
    id: u32 = 0, // Use this value to find the correct player input.
};

/// Entities with this component have associated text.
pub const Txt = struct {
    string: [:0]const u8 = "", // TODO: use hash instead of slice
    color: u32 = 0xFFFFFFFF,
    font_size: u8 = 24,
    subpos: @Vector(2, i32) = .{ 0, 0 },
    draw: bool = true, // This is very ugly, but is useful for menu items. Change if needed. (Use dynamic strings??)
};

/// Entities with this component have an associated texture.
pub const Tex = struct {
    texture_hash: u64 = AssetManager.default_hash, // TODO: add default texture to renderer/assets?
    u: u32 = 0,
    v: u32 = 0,
    w: u32 = 1,
    h: u32 = 1,
    subpos: @Vector(2, i32) = .{ 0, 0 },
    tint: rl.Color = rl.Color.white, // TODO: does this work for serialization?
    rotate: enum { R0, R90, R180, R270 } = .R0,
    flip_horizontal: bool = false,
    flip_vertical: bool = false,
};

/// Entities with this component are animated.
pub const Anm = struct {
    subframe: u32 = 0,
    interval: u32 = 1,
    animation: Animation = Animation.Default,
    looping: bool = true,
};

/// Entities with this component can count.
/// To model a timer that calls a function after a certain number of ticks, set the id to correspond to a specific function.
/// Then, create a ticker system that updates the counter and calls the correct function if the id matches and if the counter is high enough.
/// Resetting the counter should then result in a looping timer.
pub const Ctr = struct {
    id: u32 = 0,
    counter: u32 = 0,
};

/// Entities with this component are airborne.
pub const Air = struct {};

/// Entities with this component are jumping.
/// Should be removed in favor of input buffering.
pub const Jmp = struct {};

/// Entities with this component are bounded.
/// Can be used to model box-like containers such as level bounds for players or wrapping bounds for scrolling backgrounds and text.
pub const Bnd = struct {
    bounds: struct { left: i32, right: i32, top: i32, bottom: i32 } = .{
        .left = 0,
        .right = 0,
        .top = 0,
        .bottom = 0,
    },
};

/// Entities with this component have a unique identifier.
pub const Uid = struct {
    uid: u32 = 0,
};
