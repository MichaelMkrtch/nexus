const std = @import("std");
const steam_local = @import("steam/steam_local.zig");
const steam_types = @import("steam/steam_types.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    std.debug.print("=== Steam Library Test ===\n", .{});

    const games = steam_local.getInstalledGames(allocator) catch |err| {
        std.debug.print("ERROR: Failed to load games: {s}\n", .{@errorName(err)});
        return;
    };

    defer steam_types.freeGames(allocator, games);

    if (games.len == 0) {
        std.debug.print("No installed Steam games detected.\n", .{});
        return;
    }

    std.debug.print("Detected {d} installed Steam games:\n\n", .{games.len});

    for (games) |g| {
        std.debug.print(
            "App ID: {d}\nName: {s}\nLibrary Root: {s}\nInstall Dir: {s}\nFull Path: {s}\n\n",
            .{ g.app_id, g.name, g.library_root, g.install_dir, g.full_path },
        );
    }
}
