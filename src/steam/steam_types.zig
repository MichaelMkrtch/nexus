const std = @import("std");

pub const GameId = u32;

pub const Game = struct {
    app_id: GameId,
    name: []const u8,

    // File System
    library_root: []const u8, // ex: "D:\\SteamLibrary"
    install_dir: []const u8, // ex: "Cyberpunk 2077"
    full_path: []const u8,
    exe_path: ?[]const u8, // full path to exe once resolved

    // Local Metadata
    size_on_disk: u64,

    // Future Remote Metadata
    cover_image_path: ?[]const u8,
    // TODO: tags, genres, etc.
};

// A single Steam library folder
pub const LibraryFolder = struct {
    path: []const u8, // root path (ideally no trailing slash)
};

// Keep up-to-date with struct fields
pub fn freeGame(allocator: std.mem.Allocator, game: Game) void {
    allocator.free(game.name);
    allocator.free(game.library_root);
    allocator.free(game.install_dir);
    allocator.free(game.full_path);

    if (game.exe_path) |exe| {
        allocator.free(exe);
    }

    if (game.cover_image_path) |p| {
        allocator.free(p);
    }
}

pub fn freeGames(allocator: std.mem.Allocator, games: []Game) void {
    for (games) |g| {
        freeGame(allocator, g);
    }
    allocator.free(games);
}
