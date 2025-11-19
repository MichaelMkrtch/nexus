const std = @import("std");
const steam_local = @import("steam/steam_local.zig");
const steam_types = @import("steam/steam_types.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    std.debug.print("=== Steam Library Test ===\n", .{});

    const lists = steam_local.getInstalledGames(allocator) catch |err| {
        std.debug.print("ERROR: Failed to load games: {s}\n", .{@errorName(err)});
        return;
    };
    defer steam_local.freeGameLists(allocator, lists);

    if (lists.games.len == 0 and lists.games_without_exe.len == 0) {
        std.debug.print("No installed Steam games detected.\n", .{});
        return;
    }

    if (lists.games.len > 0) {
        std.debug.print("Detected {d} installed Steam games (with resolved exe):\n\n", .{lists.games.len});

        for (lists.games) |g| {
            std.debug.print(
                "App ID: {d}\nName: {s}\nLibrary Root: {s}\nInstall Dir: {s}\nFull Path: {s}\n\n",
                .{ g.app_id, g.name, g.library_root, g.install_dir, g.full_path },
            );
        }
    } else {
        std.debug.print("No games with a resolved executable.\n", .{});
    }

    if (lists.games_without_exe.len > 0) {
        std.debug.print(
            "Warning: {d} game(s) without a resolved .exe:\n",
            .{lists.games_without_exe.len},
        );
        for (lists.games_without_exe) |g| {
            std.debug.print("  - {s} (App ID: {d})\n", .{ g.name, g.app_id });
        }
    }

    // Try launching the first game with a resolved exe, if any
    if (lists.games.len > 0) {
        std.debug.print("\nLaunching first game: {s}\n", .{lists.games[0].name});
        try steam_local.launchGame(allocator, &lists.games[0]);
    }
}
