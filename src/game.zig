const std = @import("std");
const rl = @import("raylib");
const steam_types = @import("steam/steam_types.zig");

// TODO: Consider adjusting steam_type Game struct to use sentinel string
// Do allocSentinel once in vdf parser and have sentinel string across app.
pub const Game = struct {
    title: [:0]const u8,
    steam_index: usize,
    accent: rl.Color,
};

pub fn buildUIGamesFromSteam(allocator: std.mem.Allocator, steam_games: []steam_types.Game) ![]Game {
    var list = std.ArrayList(Game){};
    errdefer list.deinit(allocator);

    for (steam_games, 0..) |game, i| {
        const name = game.name;

        const title = try allocator.allocSentinel(u8, name.len, 0);
        std.mem.copyForwards(u8, title[0..name.len], name);

        const accentColor = pickAccentColor();

        try list.append(allocator, Game{ .title = title[0..name.len :0], .steam_index = i, .accent = accentColor });
    }

    return list.toOwnedSlice(allocator);
}

pub fn freeUIGames(allocator: std.mem.Allocator, games: []Game) void {
    for (games) |g| {
        allocator.free(g.title);
    }
    allocator.free(games);
}

fn pickAccentColor() rl.Color {
    const r = randomColorChannel();
    const g = randomColorChannel();
    const b = randomColorChannel();

    return rl.Color{ .r = r, .g = g, .b = b, .a = 255 };
}

fn randomColorChannel() u8 {
    return std.crypto.random.intRangeAtMost(u8, 1, 255);
}

// pub const games = [_]Game{
//     .{ .title = "Game 1", .accent = rl.Color{ .r = 0, .g = 180, .b = 255, .a = 255 } },
//     .{ .title = "Game 2", .accent = rl.Color{ .r = 255, .g = 130, .b = 0, .a = 255 } },
//     .{ .title = "Game 3", .accent = rl.Color{ .r = 120, .g = 255, .b = 150, .a = 255 } },
//     .{ .title = "Game 4", .accent = rl.Color{ .r = 60, .g = 125, .b = 75, .a = 255 } },
//     .{ .title = "Game 5", .accent = rl.Color{ .r = 30, .g = 155, .b = 165, .a = 255 } },
//     .{ .title = "Game 6", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
//     .{ .title = "Game 7", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
//     .{ .title = "Game 8", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
//     .{ .title = "Game 9", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
//     .{ .title = "Game 10", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
// };
