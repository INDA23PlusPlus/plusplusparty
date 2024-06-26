const std = @import("std");
const rl = @import("raylib");

const Self = @This();
const Allocator = std.mem.Allocator;

const Context = struct {
    pub const hash = struct {
        pub fn hash(self: Context, key: u8) u64 {
            _ = self;
            return @intCast(key);
        }
    }.hash;
    pub const eql = struct {
        pub fn eql(self: Context, a: u8, b: u8) bool {
            _ = self;
            return a == b;
        }
    }.eql;
};

const AudioHashMap = std.HashMap(
    u8,
    rl.Sound,
    Context,
    std.hash_map.default_max_load_percentage,
);

pub const default_audio = "assets/audio/default.wav";
const audio_paths = [_][:0]const u8{
    default_audio,
    "assets/audio/attack.wav",
    "assets/audio/block.wav",
    "assets/audio/death.wav",
    "assets/audio/bounce.wav",
    "assets/audio/walk.wav",
    "assets/audio/hit.wav",
    "assets/audio/join.wav",
    "assets/audio/jump.wav",
    "assets/audio/scroll.wav",
    "assets/audio/whoosh.wav",
    "assets/audio/bonk.wav",
    "assets/audio/tick.wav",
};

audio_map: AudioHashMap,

pub fn init(alloc: Allocator) !Self {
    rl.initAudioDevice();
    var audio_hash_map = AudioHashMap.init(alloc);
    for (audio_paths) |path| {
        const key: u8 = @truncate(std.hash.Wyhash.hash(0, path));
        const sound = rl.loadSound(path);
        try audio_hash_map.put(key, sound);
    }

    return .{ .audio_map = audio_hash_map };
}

pub fn deinit(self: *Self) void {
    var iter = self.audio_map.valueIterator();
    while (iter.next()) |sound| {
        rl.unloadSound(sound.*);
    }
    self.audio_map.deinit();
    rl.closeAudioDevice();
}

pub fn path_to_key(comptime path: [:0]const u8) u8 {
    comptime {
        return @truncate(std.hash.Wyhash.hash(0, path));
    }
}
