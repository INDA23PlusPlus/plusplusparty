const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");
const constants = @import("constants.zig");
const win = @import("window.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager, window: *win.Window) void {
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    const scaling: @Vector(2, f32) = .{
        @as(f32, @floatFromInt(window.width)) / constants.world_width,
        @as(f32, @floatFromInt(window.height)) / constants.world_height,
    };

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const tex_component = query.get(ecs.component.Tex) catch unreachable;

        const tex = am.texture_map.get(tex_component.texture_hash) orelse am.texture_map.get(AssetManager.default_hash) orelse unreachable;

        // Src

        const src_x: f32 = @floatFromInt(tex_component.u * constants.asset_resolution);
        const src_y: f32 = @floatFromInt(tex_component.v * constants.asset_resolution);
        const src_w: f32 = @floatFromInt(tex_component.w * constants.asset_resolution);
        const src_h: f32 = @floatFromInt(tex_component.h * constants.asset_resolution);

        const flip_vertical: f32 = @floatFromInt(1 - 2 * @as(i32, @intFromBool(tex_component.flip_vertical)));
        const flip_horizontal: f32 = @floatFromInt(1 - 2 * @as(i32, @intFromBool(tex_component.flip_horizontal)));

        const src = rl.Rectangle{ .x = src_x, .y = src_y, .width = flip_horizontal * src_w, .height = flip_vertical * src_h };

        // Dst

        const size: f32 = @floatFromInt(tex_component.size);

        const dst_pos = @as(@Vector(2, f32), @floatFromInt(pos_component.pos + tex_component.subpos)) * scaling;

        const dst_x = dst_pos[0];
        const dst_y = dst_pos[1];
        const dst_w = src_w * scaling[0] * size;
        const dst_h = src_h * scaling[1] * size;

        const dst = rl.Rectangle{ .x = dst_x, .y = dst_y, .width = dst_w, .height = dst_h };

        const rotation = @as(f32, @floatFromInt(@intFromEnum(tex_component.rotate))) * 90.0;

        // Draw

        rl.drawTexturePro(tex, src, dst, rl.Vector2.init(0, 0), rotation, tex_component.tint);
    }

    var text_query = world.query(&.{ ecs.component.Pos, ecs.component.Txt }, &.{});

    // Draw text using the AssetManager instead of a slice also uses the correct scaling and font to look like the new standard
    while (text_query.next()) |_| {
        const pos_component = text_query.get(ecs.component.Pos) catch unreachable;
        const text_c = text_query.get(ecs.component.Txt) catch unreachable;

        const color = rl.Color.fromInt(text_c.color);
        const pos = @as(@Vector(2, f32), @floatFromInt(pos_component.pos + text_c.subpos)) * scaling;

        const font_size_scaled = @as(f32, @floatFromInt(text_c.font_size * am.font.baseSize)) * scaling[0];

        const string = am.text_map.get(text_c.hash) orelse am.text_map.get(AssetManager.default_string_hash) orelse unreachable;

        rl.drawTextEx(am.font, string, rl.Vector2.init(pos[0], pos[1]), font_size_scaled, 1, color);
    }

    if (@import("builtin").mode != .Debug) return;

    var debug_position_query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Dbg,
    }, &.{});

    while (debug_position_query.next()) |_| {
        const pos_component = debug_position_query.get(ecs.component.Pos) catch unreachable;

        const x = @as(f32, @floatFromInt(pos_component.pos[0] * window.width)) / constants.world_width;
        const y = @as(f32, @floatFromInt(pos_component.pos[1] * window.height)) / constants.world_height;

        const start_1 = rl.Vector2.init(x - 10.0, y);
        const end_1 = rl.Vector2.init(x + 10.0, y);
        const start_2 = rl.Vector2.init(x, y - 10.0);
        const end_2 = rl.Vector2.init(x, y + 10.0);

        const color = rl.Color.black.alpha(0.5);

        rl.drawLineV(start_1, end_1, color);
        rl.drawLineV(start_2, end_2, color);
    }

    var debug_movement_query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Dbg,
    }, &.{});

    while (debug_movement_query.next()) |_| {
        const pos_component = debug_movement_query.get(ecs.component.Pos) catch unreachable;
        const mov_component = debug_movement_query.get(ecs.component.Mov) catch unreachable;

        const x = @as(f32, @floatFromInt(pos_component.pos[0] * window.width)) / constants.world_width;
        const y = @as(f32, @floatFromInt(pos_component.pos[1] * window.height)) / constants.world_height;

        const start = rl.Vector2.init(x, y);
        const subpixel_end = rl.Vector2.init(
            x + @as(f32, @floatCast(mov_component.subpixel.x().toFloat())),
            y + @as(f32, @floatCast(mov_component.subpixel.y().toFloat())),
        );
        const velocity_end = rl.Vector2.init(
            x + @as(f32, @floatCast(mov_component.velocity.x().toFloat())) * 20.0,
            y + @as(f32, @floatCast(mov_component.velocity.y().toFloat())) * 20.0,
        );
        const acceleration_end = rl.Vector2.init(
            x + @as(f32, @floatCast(mov_component.acceleration.x().toFloat())) * 20.0,
            y + @as(f32, @floatCast(mov_component.acceleration.y().toFloat())) * 20.0,
        );

        const subpixel_color = rl.Color.black.alpha(0.5);
        const velocity_color = rl.Color.purple.alpha(0.5);
        const acceleration_color = rl.Color.yellow.alpha(0.5);

        rl.drawLineV(start, subpixel_end, subpixel_color);
        rl.drawLineV(start, velocity_end, velocity_color);
        rl.drawLineV(start, acceleration_end, acceleration_color);
    }

    var debug_collidable_query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Dbg,
    }, &.{});

    while (debug_collidable_query.next()) |entity| {
        const pos_component = debug_collidable_query.get(ecs.component.Pos) catch unreachable;
        const col_component = debug_collidable_query.get(ecs.component.Col) catch unreachable;

        const x = @as(f32, @floatFromInt(pos_component.pos[0] * window.width)) / constants.world_width;
        const y = @as(f32, @floatFromInt(pos_component.pos[1] * window.height)) / constants.world_height;
        const w = @as(f32, @floatFromInt(col_component.dim[1] * window.width)) / constants.world_width;
        const h = @as(f32, @floatFromInt(col_component.dim[1] * window.height)) / constants.world_height;

        const rec = rl.Rectangle.init(x, y, w, h);
        var color = rl.Color.blue.alpha(0.5);

        if (world.checkSignature(entity, &.{ecs.component.Plr}, &.{})) {
            color = rl.Color.green.alpha(0.5);
        } else if (world.checkSignature(entity, &.{ecs.component.Atk}, &.{})) {
            color = rl.Color.red.alpha(0.5);
        }

        rl.drawRectangleRec(rec, color);
    }
}
