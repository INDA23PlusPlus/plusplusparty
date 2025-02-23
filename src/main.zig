const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const playback = @import("playback.zig");
const ecs = @import("ecs/ecs.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");

const SimulationCache = @import("SimulationCache.zig");
const AssetManager = @import("AssetManager.zig");
const AudioManager = @import("AudioManager.zig");
const Controller = @import("Controller.zig");
const InputMerger = @import("InputMerger.zig");
const Invariables = @import("Invariables.zig");
const NetworkingQueue = @import("NetworkingQueue.zig");

const minigames_list = @import("minigames/list.zig").list;

/// How many resimulation steps can be performed each graphical frame.
/// This is used for catching up to the server elapsed_tick.
pub const max_simulations_per_frame = 512;

/// We introduce an input delay on purpose such that there is a chance that the
/// input travels to the server in time to avoid resimulations.
/// A low value is very optimistic...
const useful_input_delay = 1;

/// The maximum number of frames that the client may be ahead of the known_server_tick before
/// the client will reset its newest_local_input_tick to prevent further resimulations into
/// the future.
const max_allowed_time_travel_to_future = 8;

/// How many packets the client may be behind and still send input packets
/// to the server.
const max_allowed_missing_packets = 8;

/// The max amount of unreceived inputs from the server
/// that the client will tolerate before pausing simulation.
const max_allowed_behind_time_simulations = 64;

fn findMinigameID(preferred_minigame: []const u8) u32 {
    for (minigames_list, 0..) |mg, i| {
        if (std.mem.eql(u8, mg.name, preferred_minigame)) {
            return @truncate(i);
        }
    }

    std.debug.print("here is a list of possible minigames:\n", .{});
    for (minigames_list) |minigame| {
        std.debug.print("\t{s}\n", .{minigame.name});
    }
    std.debug.panic("unknown minigame: {s}", .{preferred_minigame});
}

const StartNetRole = enum {
    client,
    server,
    local,
};

const LaunchErrors = error{UnknownArg};

const LaunchOptions = struct {
    start_as_role: StartNetRole = StartNetRole.local,
    force_wasd: bool = false,
    force_ijkl: bool = false,
    force_minigame: u32 = 1,
    hostname: []const u8 = "127.0.0.1",
    port: u16 = 8080,

    /// How many players to wait for until leaving the wait_for_input minigame.
    min_players: u16 = 1, // TODO: Make sure it is synched. Or remove it from release as this is mostly for debugging.

    fn parse() !LaunchOptions {
        var result = LaunchOptions{};
        var mem: [1024]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&mem);
        const allocator = alloc.allocator();
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip the filename.
        _ = args.next();

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "server")) {
                result.start_as_role = .server;
            } else if (std.mem.eql(u8, arg, "client")) {
                result.start_as_role = .client;
            } else if (std.mem.eql(u8, arg, "local")) {
                result.start_as_role = .local;
            } else if (std.mem.eql(u8, arg, "--wasd")) {
                result.force_wasd = true;
            } else if (std.mem.eql(u8, arg, "--ijkl")) {
                result.force_ijkl = true;
            } else if (std.mem.eql(u8, arg, "--minigame")) {
                result.force_minigame = findMinigameID(args.next() orelse "");
                std.debug.print("will launch minigame {d}\n", .{result.force_minigame});
            } else if (std.mem.eql(u8, arg, "--hostname")) {
                result.hostname = args.next() orelse "";
            } else if (std.mem.eql(u8, arg, "--port")) {
                result.port = try std.fmt.parseInt(u16, args.next() orelse "missing", 10);
            } else if (std.mem.eql(u8, arg, "--min-players")) {
                result.min_players = try std.fmt.parseInt(u16, args.next() orelse "missing", 10);
            } else {
                std.debug.print("unknown argument: {s}\n", .{arg});
                return error.UnknownArg;
            }
        }

        return result;
    }
};

pub fn submitInputs(controllers: []Controller, input_merger: *InputMerger, input_tick: u64, main_thread_queue: *NetworkingQueue) void {
    var players_affected = input.empty_player_bit_set;
    const data = input_merger.buttons.items[input_tick];
    for (controllers) |controller| {
        if (!controller.isAssigned()) {
            continue;
        }
        players_affected.set(controller.input_index);
    }
    main_thread_queue.outgoing_data[main_thread_queue.outgoing_data_count] = .{
        .type = .input,
        .tick = input_tick,
        .data = data,
        .players = players_affected,
    };
    main_thread_queue.outgoing_data_count += 1;
}

pub fn main() !void {
    const launch_options = try LaunchOptions.parse();

    var window = win.Window.init(960, 540); // 960, 540
    defer window.deinit();

    var static_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const static_allocator = static_arena.allocator();
    defer static_arena.deinit();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const frame_allocator = frame_arena.allocator();
    defer frame_arena.deinit();

    var assets = AssetManager.init(static_allocator);
    defer assets.deinit();

    var audm = try AudioManager.init(static_allocator);
    defer audm.deinit();

    var simulation_cache = SimulationCache{};
    simulation_cache.start_state.meta.preferred_minigame_id = launch_options.force_minigame;
    simulation_cache.start_state.meta.min_players = launch_options.min_players;
    simulation_cache.reset();

    var input_merger = try InputMerger.init(std.heap.page_allocator);

    var controllers = Controller.DefaultControllers;

    var main_thread_queue = NetworkingQueue{};
    var net_thread_queue = NetworkingQueue{};

    var owned_players = input.empty_player_bit_set;

    // Force WASD or IJKL for games that do not support hot-joining.
    if (launch_options.force_wasd) {
        controllers[0].assignment_state = .wants_assignment;
    }
    if (launch_options.force_ijkl) {
        controllers[1].assignment_state = .wants_assignment;
    }

    // TODO: This code should not be needed anymore.
    // If this is not done, then we desynch. Maybe there is a prettier solution
    // to forced input assignments. But this works, so too bad!
    // In other words, we make sure that other clients know about the forceAutoAssigns.
    // If no forceAutoAssign has happened, then all of the controllers will be unassigned at this stage.
    // So the call can't hurt anyone.
    //submitInputs(&controllers, &input_merger, 1, &main_thread_queue);

    // Networking
    if (launch_options.start_as_role == .client) {
        std.debug.print("starting client thread\n", .{});
        if (std.mem.eql(u8, launch_options.hostname, "")) {
            @panic("missing hostname parameter");
        }
        try networking.startClient(&net_thread_queue, launch_options.hostname, launch_options.port);
    } else if (launch_options.start_as_role == .server) {
        std.debug.print("starting server thread\n", .{});
        try networking.startServer(&net_thread_queue, launch_options.port);
    } else {
        // If running locally, then every player is up for grabs.
        owned_players = input.full_player_bit_set;

        // Server timeline length is 0 if we are playing locally.
        main_thread_queue.server_total_packet_count = 0;

        std.debug.print("warning: multiplayer is disabled\n", .{});
    }

    if (launch_options.start_as_role != .local and launch_options.force_minigame != 1) {
        // TODO: To solve this, we should synchronize this info to all players such that we retain determinism.
        std.debug.print("warning: using --minigame and multiplayer is currently unsafe\n", .{});
    }

    const invariables = Invariables{
        .minigames_list = &minigames_list,
        .arena = frame_allocator,
    };

    // Used by networking code.
    var rewind_to_tick: u64 = std.math.maxInt(u64);
    var received_server_tick: u64 = 0;
    var newest_local_input_tick: u64 = 0;

    // Used to know if we are still synching old packets.
    // If we are, then simulation & input might be pointless.
    var total_server_packets_recevied: u64 = 0;

    // var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // TODO: Perhaps a delay should be added to that (to non-local mode)
    // TODO: the networking thread has time to receive some updates?
    // TOOD: Or maybe something smarter like waiting for the first packet.

    // Game loop
    while (window.running) {
        // Fetch input.
        const tick = simulation_cache.head_tick_elapsed;

        const input_tick_delayed = tick + 1 + useful_input_delay;

        // TODO: This could probably be moved further down.
        // Make sure that the timeline extends far enough for the input polling to work.
        try input_merger.extendTimeline(std.heap.page_allocator, input_tick_delayed);

        // Make sure we have the newest inputs from the server.
        if (launch_options.start_as_role != .local) {
            main_thread_queue.interchange(&net_thread_queue);
        }

        // Ingest the updates.
        for (main_thread_queue.incoming_data[0..main_thread_queue.incoming_data_count]) |packet| {
            total_server_packets_recevied += 1;
            received_server_tick = @max(packet.tick, received_server_tick);

            var player_iterator = packet.players.iterator(.{});
            std.debug.print("received remoteUpdate at tick {d} player mask {b}\n", .{packet.tick, packet.players.mask});
            while (player_iterator.next()) |player| {
                switch (packet.type) {
                    .undo => input_merger.undoUpdate(@truncate(player), packet.tick),

                    .player_assignments => owned_players = packet.players,

                    .input =>  if (try input_merger.remoteUpdate(std.heap.page_allocator, @truncate(player), packet.data[player], packet.tick)) {
                        std.debug.assert(packet.tick != 0);
                        rewind_to_tick = @min(packet.tick -| 1, rewind_to_tick);
                    }
                }
            }
        }
        main_thread_queue.incoming_data_count = 0;

        main_thread_queue.wanted_player_count = Controller.pollAll(&controllers, input_merger.buttons.items[input_tick_delayed - 1]);

        // We only try to update the timeline if we are not too far back in the past.
        const close_enough_for_inputs = main_thread_queue.server_total_packet_count -| max_allowed_missing_packets < total_server_packets_recevied;

        // We can only get local input, if we have the ability to send it. If we can't send it, we
        // mustn't accept local input as that could cause desynchs.
        const has_space_for_inputs = main_thread_queue.outgoing_data_count < main_thread_queue.outgoing_data.len;

        if (close_enough_for_inputs and has_space_for_inputs) {
            Controller.autoAssign(&controllers, owned_players);

            std.debug.print("setting local {d}\n", .{input_tick_delayed});
            try input_merger.localUpdate(&controllers, input_tick_delayed);

            // Tell the networking thread about the changes we just made to the timeline.
            submitInputs(&controllers, &input_merger, input_tick_delayed, &main_thread_queue);

            newest_local_input_tick = @max(newest_local_input_tick, input_tick_delayed);
        } else {
            if (has_space_for_inputs) {
                std.debug.print("too far back in the past to take input as server has length {d} and client has tick {d}\n", .{main_thread_queue.server_total_packet_count, input_tick_delayed});
            } else {
                std.debug.print("unable to send further inputs as too many have been sent without answer\n", .{});
            }
        }

        if (launch_options.start_as_role == .local) {
            // Make sure we can scream into the void as much as we wish.
            main_thread_queue.outgoing_data_count = 0;

            // Make sure optimizations in other places don't think that
            // we are lagging behind while running local mode.
            received_server_tick = tick;

            total_server_packets_recevied = std.math.maxInt(u64);
        } else {
            main_thread_queue.interchange(&net_thread_queue);
        }

         if (newest_local_input_tick > received_server_tick + max_allowed_time_travel_to_future) {
            // If we stray too far away from the known_server_tick, we reset
            // the variable such that resimulation doesn't take us too far
            // into the future.
            newest_local_input_tick = 0;
        }

        // Now that both remote inputs and local inputs have been inserted. We must fix our predictions.
        rewind_to_tick = @min(rewind_to_tick, input_merger.fixInputPredictions());

        if (rewind_to_tick < simulation_cache.head_tick_elapsed) {
            //std.debug.print("rewind to {d}\n", .{rewind_to_tick});
            simulation_cache.rewind(rewind_to_tick);

            // The rewind is done. Reset it so that next tick
            // doesn't also rewind.
            rewind_to_tick = std.math.maxInt(u64);
        }

        const debug_key_down = rl.isKeyDown(rl.KeyboardKey.key_p);
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_one)) {
            std.debug.print("debug reset activated\n", .{});
            simulation_cache.rewind(0);
        }
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_two)) {
            const file = std.io.getStdErr();
            const writer = file.writer();
            try input_merger.dumpInputs((tick >> 9) << 9, writer);
        }
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_four)) {
            const until = (tick >> 9) << 9;
            std.debug.print("checksum until {d} is {x}\n", .{until, input_merger.createChecksum(until)});
        }

        // benchmarker.start();

        for (0..max_simulations_per_frame) |_| {
            // We check tick > max_allowed_behind_time_simulations such that people can join where time is not ticking. This is a ugly hack really.
            if (!close_enough_for_inputs and tick > max_allowed_behind_time_simulations) {
                // We know that we are missing a lot of input data. Simulating right now would be a waste.
                // Instead we wait for more input data to arrive before starting to simulate again.
                std.debug.print("game is paused while inputs are transferred\n", .{});
                break;
            }

            // All code that controls how objects behave over time in our game
            // should be placed inside of the simulate procedure as the simulate procedure
            // is called in other places. Not doing so will lead to inconsistencies.
            if (simulation_cache.head_tick_elapsed < input_merger.buttons.items.len) {
                const timeline_to_tick = input.Timeline{ .buttons = input_merger.buttons.items[0 .. simulation_cache.head_tick_elapsed + 1] };
                try simulation_cache.simulate(timeline_to_tick, invariables);
            }
            _ = frame_arena.reset(.retain_capacity);

            // TOOD: Currently, this code does not allow different clients to run with different useful_input_delays.
            // TODO: This is because the server is unable to decide what the current tick is by itself, and just uses the highest tick it has found.
            // TODO: But this means that if one client has a really high useful_input_delay, then time will speed up for
            // TODO: Other clients. Which is really funny because that will in turn speed up the time for all clients.

            const close_to_server = simulation_cache.head_tick_elapsed >= received_server_tick -| useful_input_delay;
            const close_to_local = simulation_cache.head_tick_elapsed >= newest_local_input_tick -| useful_input_delay;

            if (close_to_server and close_to_local) {
                // We have caught up. No need to do extra simulation steps now.
                break;
            }
        }

        // benchmarker.stop();
        // if (benchmarker.laps % 360 == 0) {
        //     try benchmarker.write();
        //     benchmarker.reset();
        // }

        // Begin rendering.
        window.update();
        rl.beginDrawing();
        rl.clearBackground(rl.Color.white);
        render.update(&simulation_cache.latest().world, &assets, &window);

        // Stop rendering.
        rl.endDrawing();

        playback.update(&simulation_cache.latest().world, &audm);
    }
}
