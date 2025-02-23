const std = @import("std");
const input = @import("input.zig");

const PacketType = enum { input, undo, player_assignments };

pub const Packet = struct { tick: u64, data: input.AllPlayerButtons, players: input.PlayerBitSet, type: PacketType };
const max_backlog = 1024;

rw_lock: std.Thread.RwLock = .{},

incoming_data: [max_backlog]Packet = undefined,
incoming_data_count: u64 = 0,

outgoing_data: [max_backlog]Packet = undefined,
outgoing_data_count: u64 = 0,

/// The total amount of input packets that the server has received.
/// A high value prevents the client from acting before it has even 
/// had the chance to receive some inptuts from the server.
server_total_packet_count: u64 = std.math.maxInt(u64),

/// How many players does the client wish to control in total (or atleast).
wanted_player_count: u32 = 0,

const Self = @This();

pub fn interchange(self: *Self, other: *Self) void {
    self.rw_lock.lock();
    other.rw_lock.lock();

    //std.debug.print("attempt interchange: {d} {d}\n", .{self.outgoing_data_len, other.incoming_data_count});
    while (self.outgoing_data_count > 0 and other.incoming_data_count < max_backlog) {
        const new_outgoing_len = self.outgoing_data_count - 1;
        self.outgoing_data_count = new_outgoing_len;
        other.incoming_data[other.incoming_data_count] = self.outgoing_data[new_outgoing_len];
        other.incoming_data_count += 1;
    }

    while (self.incoming_data_count < max_backlog and other.outgoing_data_count > 0) {
        const new_outgoing_len = other.outgoing_data_count - 1;
        other.outgoing_data_count = new_outgoing_len;
        self.incoming_data[self.incoming_data_count] = other.outgoing_data[new_outgoing_len];
        self.incoming_data_count += 1;
    }

    // Transfer some scalars. This operation is not symmetric.
    // Results will vary between a.interchange(b) and b.interchange(a).
    // TODO: for this reason, a better name for the procedure should be found.
    self.server_total_packet_count = other.server_total_packet_count;

    other.wanted_player_count = self.wanted_player_count;

    self.rw_lock.unlock();
    other.rw_lock.unlock();
}
