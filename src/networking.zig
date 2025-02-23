// TODO: Old method, might be related:
// TODO: To get a desynch, hide the window such that the local-client stops receiving input.
// TODO: Wait a minute. Then open the window and start spamming random directions. You will desynch if you are lucky by a little.
// TODO: This must be fixed! Their seems to be a little window of time where inputs are allowed to be sent because we are close enough to the server timeline, but the inputs are already overriden by
// TODO: other factors.

const std = @import("std");
const constants = @import("constants.zig");

const sim = @import("simulation.zig");
const ecs = @import("ecs/world.zig");
const cbor = @import("cbor.zig");
const input = @import("input.zig");

const NetworkingQueue = @import("NetworkingQueue.zig");

const MultiplayerError = error {
    unknown_packet,
};

const PacketType = enum(u8) {
    input = 0,
    undo = 1,
    player_assignments = 2,
};

const InputPacket = struct {
    inputs: input.AllPlayerButtons,

    /// What player inputs are affected.
    players: input.PlayerBitSet,

    /// Change in tick count relative to previous InputPacket.
    tick_delta: i16,
};

const UndoPacket = struct {
    tick: u64,
    players: input.PlayerBitSet,
};

const PlayerAssignmentsPacket = struct {};

const ServerPacket = union(PacketType) {
    input: InputPacket,
    undo: UndoPacket,
    player_assignments: PlayerAssignmentsPacket,
};

const ConnectionType = enum(u8) {
    /// The connection/client slot can be assigned to a new connection.
    empty,

    /// This slot is reserved for the local client.
    local,

    /// Already occupied by a remote client.
    remote,

    /// Disconnecting. No longer accepting new packages. Once the last package is processed, slot will be empty.
    disconnecting,

    fn is_playing(self: ConnectionType) bool {
        return self == .local or self == .remote;
    }
};

const max_net_packet_size = 65535 - 8;

const max_packets_to_send = 256;


/// Just a helper to avoid @intCast everywhere.
fn nextTick(current: u64, delta: i16) u64 {
    const as_int: i64 = @intCast(current);
    return @intCast(as_int + delta);
}

const ClientPacket = struct {
    packet: NetworkingQueue.Packet,
    conn_index: u32,
    is_disconnect: bool = false,
};

fn debugPacket(packet: []const u8) void {
    // Print the CBOR contents.
    var debug_log_buffer: [1024]u8 = undefined;
    var debug_fb = std.io.fixedBufferStream(&debug_log_buffer);
    const debug_writer = debug_fb.writer();
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    const debug_len = ctx.toString(debug_writer) catch |e| {
        const formatter = std.fmt.fmtSliceHexUpper(packet);
        std.debug.print("could not parse package ({any}): {any}\n", .{ e, formatter });
        return;
    };
    std.debug.print("parsed package: {s}\n", .{debug_log_buffer[0..debug_len]});
}

const PacketBuffer = struct {
    buffer: [max_net_packet_size * 2]u8 = undefined,
    index: u32 = 0,
    to_remove: u32 = 0,

    inline fn toPacket(self: *PacketBuffer, to_add: []const u8) []const u8 {
        // Move old packet out of the way!
        const old_to_remove = self.to_remove;
        if (old_to_remove > 0) {
            std.mem.copyForwards(u8, self.buffer[0..self.index], self.buffer[self.to_remove..self.index]);
            self.index -= old_to_remove;
            self.to_remove = 0;
        }

        std.debug.assert(self.to_remove == 0);

        if (to_add.len + self.index > self.buffer.len) {
            std.debug.panic("packet buffer will overflow", .{});
        }

        // Regions do not overlap, so this is safe.
        if (to_add.len != 0) {
            @memcpy(self.buffer[self.index .. self.index + to_add.len], to_add);
            self.index += @truncate(to_add.len);
        }

        if (self.index < 4) {
            // Not even the packet length has arrived... Sigh.
            //std.debug.print("waiting for length {d}\n", .{self.index});
            return "";
        }

        const expected_packet_len = std.mem.readInt(u32, self.buffer[0..4], std.builtin.Endian.little);
        const with_header_len = expected_packet_len + 4;

        if (with_header_len > self.index) {
            // Full packet has not arrvied yet.
            //std.debug.print("waiting for packet {d} {d}\n", .{ with_header_len, self.index });
            return "";
        }

        //std.debug.print("reading package of size {d} {d} {d}\n", .{ expected_packet_len, self.index, self.to_remove });

        self.to_remove = with_header_len;
        return self.buffer[4..with_header_len];
    }
};

const PacketHistory = std.ArrayListUnmanaged(ServerPacket);

const NetServerData = struct {
    /// All packets ever broadcasted, not ordered by tick but in order of arrival.
    packet_history: PacketHistory,

    /// The tick value of the last entry in all_packets_sent.
    packet_history_tick: i64 = 0,

    /// The connection status of every client/connection slot.
    conns_type: [constants.max_connected_count]ConnectionType = [_]ConnectionType{.empty} ** constants.max_connected_count,

    /// The underlying OS handles for every client.
    conns_sockets: [constants.max_connected_count]std.posix.socket_t = undefined,

    /// Because TCP over IP is a stream protocol we must chunk the packets using a PacketBuffer.
    conns_packet_buffer: [constants.max_connected_count]PacketBuffer = undefined,

    /// How many packets we may send this client.
    conns_packet_budget: [constants.max_connected_count]u32 = undefined,

    /// How far into the unchronological_inputs array we have sent to the client.
    conns_packets_sent: [constants.max_connected_count]u64 = undefined,

    /// The last tick that was sent to the client.
    conns_sent_tick: [constants.max_connected_count]u64 = undefined,

    /// Modified by the pollSockets procedure.
    conns_should_read: [constants.max_connected_count]bool = undefined,

    /// Used to know on which tick to place the disconnect packet.
    conns_last_seen_tick: [constants.max_connected_count]u64 = undefined,

    /// What player does the server thing a certain client is trying to control.
    /// This affects disconnect logic.
    conns_owned_players: [constants.max_connected_count]input.PlayerBitSet = undefined,

    /// The amount of owned players that this connection wants.
    conns_wanted_player_count: [constants.max_connected_count]u32 = undefined,

    fn connectSlot(self: *NetServerData) ?usize {
        for (self.conns_type, 0..) |t, i| {
            if (t != .empty) {
                continue;
            }
            self.conns_type[i] = .remote;
            self.conns_packet_buffer[i] = .{};
            self.conns_should_read[i] = false;
            self.conns_packet_budget[i] = 1;
            self.conns_packets_sent[i] = 0;
            self.conns_sent_tick[i] = 0;
            self.conns_last_seen_tick[i] = 0;
            self.conns_wanted_player_count[i] = 0;
            self.conns_owned_players[i] = input.empty_player_bit_set;
            return i;
        }
        return null;
    }

    fn addInputPacket(self: *NetServerData, conn_index: usize, packet: NetworkingQueue.Packet) void {
        const new_tick: i64 = @intCast(packet.tick);
        if (new_tick <= 0) {
            // TODO: Handle by disconnecting player instead.
            std.debug.panic("bad package from client as tick <= 0", .{});
        }
        const tick_delta: i64 = @as(i64, @intCast(new_tick)) - self.packet_history_tick;
        if (tick_delta >= std.math.maxInt(i16) or tick_delta <= std.math.minInt(i16) / 4) {
            // The input is too far back in time in order to express as a 16 bit number.
            // This means that we can not synch it to others. So we tell the client to undo.
            self.packet_history.append(std.heap.page_allocator, .{.undo = .{
                .players = packet.players,
                .tick = packet.tick,
            }}) catch @panic("could not expand unchronological_inputs");
            return;

            // TODO: Use better constants for the check.
        }
        self.packet_history.append(std.heap.page_allocator, .{ .input = .{
            .inputs = packet.data,
            .players = packet.players,
            .tick_delta = @truncate(tick_delta),
        }}) catch @panic("could not expand unchronological_inputs");
        self.packet_history_tick = new_tick;

        self.conns_last_seen_tick[conn_index] = @max(self.conns_last_seen_tick[conn_index], @as(u64, @intCast(new_tick)));
    }

    /// Gives out players to those that want them.
    fn assignPlayers(self: *NetServerData) void {
        var owned_players = input.empty_player_bit_set;
        var did_assign = false;

        for (self.conns_type, self.conns_owned_players) |conn_type, owned| {
            if (conn_type.is_playing()) {
                owned_players.setUnion(owned);
            }
        }

        var unowned_players_iterator = owned_players.complement().iterator(.{});

        for(0..constants.max_player_count) |conn_index| {
            if (!self.conns_type[conn_index].is_playing()) {
                continue;
            }

            while (self.conns_owned_players[conn_index].count() < self.conns_wanted_player_count[conn_index]) {
                if (unowned_players_iterator.next()) |player_index| {
                    self.conns_owned_players[conn_index].set(player_index);
                    did_assign = true;
                } else {
                    // Out of players. Ignore the request.
                    break;
                }
            }
        }

        if (did_assign) {
            self.packet_history.append(std.heap.page_allocator, .{ .player_assignments = .{}})
                catch @panic("could not expand unchronological_inputs");
        }
    }
};

fn parsePacketFromClient(server_data: *NetServerData, conn_index: usize, packet: []const u8) !void {
    if (packet.len == 0) {
        return;
    }

    //debugPacket(packet);

    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var input_synch = try ctx.readArray();
    std.debug.assert(input_synch.items == 4);
    _ = try input_synch.readU64(); //client.tick_acknowledged = @max(client.tick_acknowledged, try input_synch.readU64());
    server_data.conns_packet_budget[conn_index] = @truncate(try input_synch.readU64());
    //std.debug.print("packet from client with tick ack {}\n", .{new_tick_acknowledged});

    server_data.conns_wanted_player_count[conn_index] = @truncate(try input_synch.readU64());

    var all_packets = try input_synch.readArray();

    for (0..all_packets.items) |_| {
        var tick_info = try all_packets.readArray();
        std.debug.assert(tick_info.items == 2);
        const input_tick_index = try tick_info.readU64();

        var all_inputs = try tick_info.readArray();

        var players_affected = input.empty_player_bit_set;
        var player_buttons = input.default_input_state;

        if (input_tick_index == 0) {
            std.debug.panic("server tried to change player input states for tick 0", .{});
        }

        for (0..all_inputs.items) |_| {
            var player_input = try all_inputs.readArray();
            std.debug.assert(player_input.items == 4);
            const player_index = try player_input.readU64();
            const dpad = try player_input.readU64();
            const button_a = try player_input.readU64();
            const button_b = try player_input.readU64();

            if (player_index >= constants.max_player_count) {
                std.debug.panic("client seems to support more players than client does", .{});
            }

            player_buttons[player_index] = .{
                .dpad = @enumFromInt(dpad),
                .button_a = @enumFromInt(button_a),
                .button_b = @enumFromInt(button_b),
            };

            players_affected.set(player_index);

            try player_input.readEnd();
        }

        try all_inputs.readEnd();
        try tick_info.readEnd();

        server_data.addInputPacket(conn_index, .{
            .type = .input,
            .tick = @truncate(input_tick_index),
            .data = player_buttons,
            .players = players_affected,
        });
    }
    try all_packets.readEnd();
    try input_synch.readEnd();
}

fn clientConnected(server_data: *NetServerData, conn: std.net.Server.Connection) void {
    std.debug.print("incoming player\n", .{});

    if (server_data.connectSlot()) |slot| {
        server_data.conns_sockets[slot] = conn.stream.handle;
    } else {
        std.log.warn("too many players", .{});
        conn.stream.close();
    }
}

fn sendUpdatesToLocalClient(server_data: *NetServerData, networking_queue: *NetworkingQueue, conn_index: usize, send_start: u64, send_end: u64) void {
    for (send_start..send_end) |packet_index| {
        const packet = server_data.packet_history.items[packet_index];

        if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
            std.debug.panic("tried to send too much data to client", .{});
        }

        networking_queue.outgoing_data[networking_queue.outgoing_data_count] = switch (packet) {
            .input => |input_packet| blk: {
                const new_tick = nextTick(server_data.conns_sent_tick[conn_index], input_packet.tick_delta);
                server_data.conns_sent_tick[conn_index] = new_tick;

                break :blk .{
                    .tick = new_tick,
                    .players = input_packet.players,
                    .data = input_packet.inputs,
                    .type = .input,
                };
            },
            .undo => |undo_packet| .{
                .tick = undo_packet.tick,
                .players = undo_packet.players,
                .data = input.default_input_state,
                .type = .undo,
            },
            .player_assignments => .{
                .tick = 0,
                .players = server_data.conns_owned_players[conn_index],
                .data = input.default_input_state,
                .type = .player_assignments
            },
        };

        //std.debug.print("sending to local an update for player 0b{b} at tick {d}\n", .{is_certain.mask, tick_index});
        networking_queue.outgoing_data_count += 1;
    }

    networking_queue.server_total_packet_count = server_data.packet_history.items.len;
}

fn serializeInputPacket(writer: anytype, input_packet: InputPacket, tick: u64) !void {
    try cbor.writeArrayHeader(writer, 3);
    try cbor.writeUint(writer, @intFromEnum(PacketType.input));
    try cbor.writeUint(writer, tick);
    try cbor.writeArrayHeader(writer, input_packet.players.count());
    for (0..constants.max_player_count) |player| {
        if (!input_packet.players.isSet(player)) {
            // No point in sending something that we are unsure of.
            continue;
        }
        const player_input = input_packet.inputs[player];
        try cbor.writeArrayHeader(writer, 4);
        try cbor.writeUint(writer, player);
        try cbor.writeUint(writer, @intFromEnum(player_input.dpad));
        try cbor.writeUint(writer, @intFromEnum(player_input.button_a));
        try cbor.writeUint(writer, @intFromEnum(player_input.button_b));

    }
}

fn serializeUndoPacket(writer: anytype, undo_packet: UndoPacket) !void {
    try cbor.writeArrayHeader(writer, 3);
    try cbor.writeUint(writer, @intFromEnum(PacketType.undo));
    try cbor.writeUint(writer, undo_packet.tick);

    try cbor.writeArrayHeader(writer, undo_packet.players.count());
    var iterator = undo_packet.players.iterator(.{});
    while (iterator.next()) |player| {
        try cbor.writeUint(writer, player);
    }
}

fn serializePlayerAssignmentPacket(writer: anytype, player_assignments: input.PlayerBitSet) !void {
    try cbor.writeArrayHeader(writer, 2);
    try cbor.writeUint(writer, @intFromEnum(PacketType.player_assignments));

    try cbor.writeArrayHeader(writer, player_assignments.count());
    var iterator = player_assignments.iterator(.{});
    while (iterator.next()) |player| {
        try cbor.writeUint(writer, player);
    }
}

fn sendUpdatesToRemoteClient(server_data: *NetServerData, conn_index: usize, send_start: u64, send_end: u64) !void {
    var send_buffer: [max_net_packet_size]u8 = undefined;
    const send_amount = send_end - send_start;
    var fb = std.io.fixedBufferStream(send_buffer[4..]);
    const writer = fb.writer();
    try cbor.writeArrayHeader(writer, 2);

    // We give the client this information so that it knows if it is really far behind.
    try cbor.writeUint(writer, server_data.packet_history.items.len);

    try cbor.writeArrayHeader(writer, send_amount);
    for (send_start..send_end) |packet_index| {
        const packet = server_data.packet_history.items[packet_index];
        switch(packet) {
            .input => |input_packet| {
                const new_tick = nextTick(server_data.conns_sent_tick[conn_index], input_packet.tick_delta);
                server_data.conns_sent_tick[conn_index] = new_tick;
                try serializeInputPacket(writer, input_packet, new_tick);
            },
            .undo => |undo_packet| try serializeUndoPacket(writer, undo_packet),
            .player_assignments => try serializePlayerAssignmentPacket(writer, server_data.conns_owned_players[conn_index]),
        }
    }

    //std.debug.print("sending packet of length {d}\n", .{fb.pos});

    // There is an explanation for this line in this file. Just search for writeInt.
    std.mem.writeInt(std.math.ByteAlignedInt(u32), send_buffer[0..4], @truncate(fb.pos), std.builtin.Endian.little);

    _ = std.posix.send(server_data.conns_sockets[conn_index], send_buffer[0 .. fb.pos + 4], 0) catch |e| switch (e) {
        error.WouldBlock => 0,
        else => return e,
    };
}

// TODO: Rename to sendOutgoingPackets or something like that
fn serverThreadQueueTransfer(server_data: *NetServerData, networking_queue: *NetworkingQueue) !void {
    networking_queue.rw_lock.lock();

    // Send the updates to the clients.
    for (server_data.conns_type, 0..) |conn_type, conn_index| {

        // Send the missing inputs. But only N at the time.
        const send_start = server_data.conns_packets_sent[conn_index];

        const send_end = @min(server_data.packet_history.items.len, send_start + server_data.conns_packet_budget[conn_index]);

        if (send_end <= send_start) {
            // Nothing to send.
            continue;
        }

        if (conn_type == .empty) {
            continue;
        }

        const send_count: u32 = @truncate(send_end - send_start);

        server_data.conns_packet_budget[conn_index] -= send_count;
        server_data.conns_packets_sent[conn_index] += send_count;

        //std.debug.print("sending {any} {d} to {d} with packet bandwith {d}\n", .{conn_type, send_start, send_until, packet_count_bandwidth});

        switch (conn_type) {
            .local => sendUpdatesToLocalClient(server_data, networking_queue, conn_index, send_start, send_end),
            .remote => sendUpdatesToRemoteClient(server_data, conn_index, send_start, send_end) catch |e| {
                std.debug.print("error while sending to remote client: {any}", .{e});
                continue;
            },
            else => {},
        }
    }

    networking_queue.rw_lock.unlock();
}

/// Sets conns_should_read[index] for any socket that has available data.
/// We also use this code in the client to poll the singular connection to the server.
/// It is nice to reuse platform-level abstraction when possible.
fn pollSockets(timeout_ms: u32, conns_type: []ConnectionType, conns_sockets: []std.posix.socket_t, conns_should_read: []bool) void {
    // TODO: Ideally, the select in pollSocket would awake from networking_queue as well, oh well!

    if (@import("builtin").os.tag == .windows) {
        var read_fd_set = std.os.windows.ws2_32.fd_set{
            .fd_array = undefined,
            .fd_count = 0,
        };

        const timeval = std.os.windows.ws2_32.timeval{
            .tv_sec = 0,
            .tv_usec = @intCast(std.time.us_per_ms * timeout_ms),
        };

        var fd_count: u32 = 0;
        for (conns_type, conns_sockets) |conn_type, conn_socket| {
            if (conn_type == .remote) {
                std.debug.assert(fd_count < read_fd_set.fd_array.len);
                read_fd_set.fd_array[fd_count] = conn_socket;
                fd_count += 1;
            }
        }
        read_fd_set.fd_count = fd_count;

        const i = std.os.windows.ws2_32.select(0, &read_fd_set, null, null, &timeval);
        if (i <= 0) {
            return;
        }

        for (read_fd_set.fd_array[0..read_fd_set.fd_count]) |fd| {
            // O complexity is n^2. Luckily a read_fd_set can not be larger than 64...
            for (conns_sockets, 0..) |other, conn_index| {
                if (other == fd) {
                    conns_should_read[conn_index] = true;
                }
            }
        }
    } else {
        const INT_EVENTS = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.PRI;
        var poll_fds: [64]std.posix.pollfd = undefined;
        for (&poll_fds) |*poll_fd| {
            poll_fd.fd = -1;
            poll_fd.revents = 0;
            poll_fd.events = INT_EVENTS;
        }

        var fd_count: usize = 0;
        for (conns_type, conns_sockets) |conn_type, conn_socket| {
            if (conn_type == .remote) {
                std.debug.assert(fd_count < poll_fds.len);
                poll_fds[fd_count].fd = conn_socket;
                fd_count += 1;
            }
        }

        const i = std.posix.poll(&poll_fds, @intCast(timeout_ms)) catch {
            std.debug.print("std.posix.poll() failed\n", .{});
            return;
        };

        if (i <= 0) {
            return;
        }

        for (poll_fds[0..fd_count]) |poll_fd| {
            for (conns_sockets, 0..) |other, conn_index| {
                if (other == poll_fd.fd and poll_fd.revents & INT_EVENTS != 0) {
                    conns_should_read[conn_index] = true;
                }
            }
        }
    }
}

fn performDisconnect(server_data: *NetServerData, conn_index: u32) void {
    std.debug.print("disconnecting players {b}\n", .{server_data.conns_owned_players[conn_index].mask});
    const fd = server_data.conns_sockets[conn_index];
    server_data.conns_type[conn_index] = .disconnecting;

    const all_disconnected = [_]input.PlayerInputState{.{.dpad = .Disconnected}} ** constants.max_player_count;
    server_data.addInputPacket(conn_index, .{
        .type = .undo,
        .tick = server_data.conns_last_seen_tick[conn_index] + 1,
        .data = all_disconnected,
        .players = server_data.conns_owned_players[conn_index],
    });

    // TODO: change conns_type from disconnecting to empty somewhere appropriate.

    std.posix.close(fd);
}

fn transferPacketsFromLocalClient(server_data: *NetServerData, networking_queue: *NetworkingQueue, conn_index: usize) void {
    while (networking_queue.incoming_data_count > 0) {
        networking_queue.incoming_data_count -= 1;
        server_data.addInputPacket(conn_index, networking_queue.incoming_data[networking_queue.incoming_data_count]);
    }

    // We update each frame such that we don't accidentally send to much and crash.
    server_data.conns_packet_budget[conn_index] = @truncate(networking_queue.outgoing_data.len - networking_queue.outgoing_data_count);

    server_data.conns_wanted_player_count[conn_index] = networking_queue.wanted_player_count;
}

fn readIncomingPackets(server_data: *NetServerData, networking_queue: *NetworkingQueue) void {
    var packet_part_buf: [max_net_packet_size]u8 = undefined;
    pollSockets(10, &server_data.conns_type, &server_data.conns_sockets, &server_data.conns_should_read);
    for (&server_data.conns_packet_buffer, server_data.conns_sockets, server_data.conns_type, server_data.conns_should_read, 0..) |*packet_buffer, fd, conn_type, should_read, conn_index| {
        if (conn_type == .local) {
            transferPacketsFromLocalClient(server_data, networking_queue, @truncate(conn_index));
            continue;
        }
        if (conn_type != .remote) {
            continue;
        }
        if (!should_read) {
            continue;
        }
        server_data.conns_should_read[conn_index] = false;

        const packet_part_len = std.posix.read(fd, &packet_part_buf) catch 0;
        if (packet_part_len == 0) {
            performDisconnect(server_data, @truncate(conn_index));
            continue;
        }
        const packet_part = packet_part_buf[0..packet_part_len];

        var full_packet = packet_buffer.toPacket(packet_part);

        //std.debug.print("reading from player {d} length {d}", .{ conn_index, length });

        // The reason that we loop here is that the client has a
        // lower clock rate for sending. If we do not handle everything
        // that we managed to read immedietly, then we will only read
        // at the clock rate of the server thread. This means
        // that eventually reads will be filled with a ton of unread
        // packets.
        while (full_packet.len > 0) {
            parsePacketFromClient(server_data, conn_index, full_packet) catch |e| {
                std.debug.print("error while parsing packet of player {d}: {any}\n", .{ conn_index, e });
            };
            full_packet = packet_buffer.toPacket("");
        }
    }
}

fn serverThread(networking_queue: *NetworkingQueue, port: u16) !void {
    var server_data = NetServerData {
        .packet_history = try PacketHistory.initCapacity(std.heap.page_allocator, 1024),
    };
    defer server_data.packet_history.deinit(std.heap.page_allocator);

    if (server_data.connectSlot()) |slot| {
        // Add a local client so that the player hosting the game may also
        // interact with the game.
        server_data.conns_type[slot] = .local;
    }

    const address = try std.net.Address.parseIp("0.0.0.0", port);
    var listening = try address.listen(.{ .force_nonblocking = true });

    while (true) {
        if (listening.accept()) |new_client| {
            clientConnected(&server_data, new_client);
        } else |_| {}

        readIncomingPackets(&server_data, networking_queue);

        server_data.assignPlayers();

        try serverThreadQueueTransfer(&server_data, networking_queue);
    }
}

pub fn startServer(networking_queue: *NetworkingQueue, port: u16) !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{networking_queue, port});
}

inline fn parseInputPacket(tick_info: *cbor.Context) !NetworkingQueue.Packet {
    std.debug.assert(tick_info.items == 2);
    const input_tick_index = try tick_info.readU64();
    var all_inputs = try tick_info.readArray();

    var players_affected = input.empty_player_bit_set;
    var player_buttons = input.default_input_state;

    if (input_tick_index == 0) {
        // TODO: Perhaps handle somewhere else.
        std.debug.panic("server tried to change player input states for tick 0", .{});
    }

    for (0..all_inputs.items) |_| {
        var player_input = try all_inputs.readArray();
        std.debug.assert(player_input.items == 4);
        const player_index = try player_input.readU64();
        const dpad = try player_input.readU64();
        const button_a = try player_input.readU64();
        const button_b = try player_input.readU64();

        if (player_index >= constants.max_player_count) {
            std.debug.panic("server seems to support more players than client does", .{});
        }

        player_buttons[player_index] = .{
            .dpad = @enumFromInt(dpad),
            .button_a = @enumFromInt(button_a),
            .button_b = @enumFromInt(button_b),
        };

        players_affected.set(player_index);

        //std.debug.print("received dpad: {any} for player {d} and tick {d}\n", .{networking_queue.outgoing_data[networking_queue.outgoing_data_count].data.dpad, player_i, input_tick_index});
        //std.debug.print("received tick {d}\n", .{input_tick_index});
        try player_input.readEnd();
    }

    try all_inputs.readEnd();
    return .{
        .tick = @truncate(input_tick_index),
        .data = player_buttons,
        .players = players_affected,
        .type = .input,
    };
}

inline fn parseUndoPacket(tick_info: *cbor.Context) !NetworkingQueue.Packet {
    std.debug.assert(tick_info.items == 2);
    const input_tick_index = try tick_info.readU64();
    if (input_tick_index == 0) {
        // TODO: Perhaps handle somewhere else.
        std.debug.panic("server tried to undo player input states for tick 0", .{});
    }
    var player_list = try tick_info.readArray();

    var players_affected = input.empty_player_bit_set;

    for (0..player_list.items) |_| {
        const player_index = try player_list.readU64();

        if (player_index >= constants.max_player_count) {
            std.debug.panic("server seems to support more players than client does", .{});
        }

        players_affected.set(player_index);
    }
    try player_list.readEnd();
    return .{
        .tick = @truncate(input_tick_index),
        .data = input.default_input_state,
        .players = players_affected,
        .type = .undo,
    };
}

inline fn parsePlayerAssignmentsPacket(tick_info: *cbor.Context) !NetworkingQueue.Packet {
    std.debug.assert(tick_info.items == 1);
    var player_list = try tick_info.readArray();

    var players_affected = input.empty_player_bit_set;

    std.debug.print("players_list len {}\n", .{player_list.items});
    for (0..player_list.items) |_| {
        const player_index = try player_list.readU64();

        if (player_index >= constants.max_player_count) {
            std.debug.panic("server seems to support more players than client does", .{});
        }

        players_affected.set(player_index);
    }
    try player_list.readEnd();
    return .{
        .tick = 0,
        .data = input.default_input_state,
        .players = players_affected,
        .type = .player_assignments,
    };
}

fn handlePacketFromServer(networking_queue: *NetworkingQueue, packet: []const u8) !u64 {
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var input_synch = try ctx.readArray();
    std.debug.assert(input_synch.items == 2);
    networking_queue.server_total_packet_count = try input_synch.readU64();
    var all_packets = try input_synch.readArray();
    var newest_input_tick: u64 = 0;
    for (0..all_packets.items) |_| {
        var tick_info = try all_packets.readArray();
        const packet_type = try tick_info.readU64();
        const parsed_packet = switch (packet_type) {
            @intFromEnum(PacketType.input) => try parseInputPacket(&tick_info),
            @intFromEnum(PacketType.undo) => try parseUndoPacket(&tick_info),
            @intFromEnum(PacketType.player_assignments) => try parsePlayerAssignmentsPacket(&tick_info),
            else => return MultiplayerError.unknown_packet,
        };
        try tick_info.readEnd();

        if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
            std.debug.panic("desynch casued by networking_queue oversaturation", .{});
        }
        networking_queue.outgoing_data[networking_queue.outgoing_data_count] = parsed_packet;
        networking_queue.outgoing_data_count += 1;

        // TODO: This isn't used anymore. And could be removed.
        // All inputs were consumed for this tick. We may now ask the server
        // to send us newer inputs. We can only set this value after we are
        // sure of all inputs being consumed.
        newest_input_tick = @max(newest_input_tick, parsed_packet.tick);
    }
    try all_packets.readEnd();
    try input_synch.readEnd();

    return newest_input_tick;
}

const PollerForClient = struct {
    fd: [1]std.posix.socket_t,
    connection: [1]ConnectionType = .{ConnectionType.remote},
    should_read: [1]bool = .{false},
};

fn clientThread(networking_queue: *NetworkingQueue, hostname: []const u8, port: u16) !void {
    // We need the GPA because tcpConnectToHost needs to store the DNS lookups somewhere.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stream = try std.net.tcpConnectToHost(alloc, hostname, port);
    var poller = PollerForClient{ .fd = .{stream.handle} };

    std.debug.print("connection established\n", .{});
    var newest_input_tick: u64 = 0;

    // We need a packet buffer because TCP over IP is a stream protocl
    // and not a fragment protocol.
    var packet_buffer = PacketBuffer{};

    var packet_per_receive_bandwidth: u32 = 8;

    while (true) {
        var packet_part_buf: [max_net_packet_size]u8 = undefined;
        pollSockets(4, &poller.connection, &poller.fd, &poller.should_read);
        const should_read = poller.should_read[0];
        const packet_part_len = if (should_read) try stream.read(&packet_part_buf) else 0;
        const packet_part = packet_part_buf[0..packet_part_len];

        var full_packet = packet_buffer.toPacket(packet_part);

        var should_reduce_bandwidth = false;

        //debugPacket(full_packet);

        // Reset the poller. We don't care if it was ever set.
        poller.should_read[0] = false;

        networking_queue.rw_lock.lock();

        while (networking_queue.outgoing_data_count > networking_queue.outgoing_data.len / 2) {
            should_reduce_bandwidth = true;

            // If half the outgoing queue is filled, we should give the the
            // main thread some time to catch up.

            // First unlock it so that the main thread doesn't hang.
            networking_queue.rw_lock.unlock();

            // Give main thread some time...
            std.time.sleep(std.time.ns_per_ms * 2);

            std.debug.print("net sleeping to catch up\n", .{});

            // Lock it again so that the above check is safe.
            // Also makes the code following the while-loop safe.
            networking_queue.rw_lock.lock();

        }

        if (should_reduce_bandwidth) {
            packet_per_receive_bandwidth /= 2;
        } else {
            packet_per_receive_bandwidth += 4;
        }
        packet_per_receive_bandwidth = std.math.clamp(packet_per_receive_bandwidth, 1, max_packets_to_send);

        // The rational for this loop is the same as for the similiar
        // looking code found in the server thread.
        while (full_packet.len > 0) {
            const possibly_newer = try handlePacketFromServer(networking_queue, full_packet);
            newest_input_tick = @max(possibly_newer, newest_input_tick);
            full_packet = packet_buffer.toPacket("");
        }


        // We only send packets without input if we have received a packet.
        // Packets with input are always sent.
        const should_send = should_read or networking_queue.incoming_data_count > 0;

        var send_buffer: [max_net_packet_size]u8 = undefined;
        var fb = std.io.fixedBufferStream(send_buffer[4..]);
        const writer = fb.writer();

        try cbor.writeArrayHeader(writer, 4);
        try cbor.writeUint(writer, newest_input_tick);
        try cbor.writeUint(writer, packet_per_receive_bandwidth);
        try cbor.writeUint(writer, networking_queue.wanted_player_count);

        //std.debug.print("client is sending {}\n", .{networking_queue.incoming_data_count});
        try cbor.writeArrayHeader(writer, networking_queue.incoming_data_count);
        for (networking_queue.incoming_data[0..networking_queue.incoming_data_count]) |packet| {
            try cbor.writeArrayHeader(writer, 2);
            try cbor.writeUint(writer, packet.tick);
            try cbor.writeArrayHeader(writer, packet.players.count());
            var players = packet.players.iterator(.{});
            while (players.next()) |player_index| {
                const data = packet.data[player_index];
                try cbor.writeArrayHeader(writer, 4);
                try cbor.writeUint(writer, player_index);
                try cbor.writeUint(writer, @intFromEnum(data.dpad));
                try cbor.writeUint(writer, @intFromEnum(data.button_a));
                try cbor.writeUint(writer, @intFromEnum(data.button_b));
            }
        }
        networking_queue.incoming_data_count = 0;

        // Patch in the length of the packet encoded as 4 bytes.
        // We use little endian because that is more common nowadays.
        // Unfortunately CBOR uses big endian, so some inconsistencies exist.
        // The reason we send the length in total bytes is that TCP over IP
        // is a stream of bytes and does not distinguish between separate
        // calls of write(). And we must know where a package ends so we can
        // start reading the next.
        std.mem.writeInt(std.math.ByteAlignedInt(u32), send_buffer[0..4], @truncate(fb.pos), std.builtin.Endian.little);

        if (should_send) {
            _ = try stream.write(send_buffer[0 .. fb.pos + 4]);
        }

        networking_queue.rw_lock.unlock();
    }
}

pub fn startClient(networking_queue: *NetworkingQueue, hostname: []const u8, port: u16) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{ networking_queue, hostname, port });
}

test "packet buffer two part" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("", buffer.toPacket("\x01\x00\x00\x00"));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("Q"));
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
}

test "packet buffer directly" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("\x01\x00\x00\x00Q"));
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
}

test "packet buffer two in one" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("\x01\x00\x00\x00Q\x01\x00\x00\x00W"));
    try std.testing.expectEqualStrings("W", buffer.toPacket("\x01\x00\x00\x00A\x01\x00\x00\x00B"));
    try std.testing.expectEqualStrings("A", buffer.toPacket(""));
    try std.testing.expectEqualStrings("B", buffer.toPacket(""));
}
