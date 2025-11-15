const rl = @import("raylib");

pub const Game = struct { title: [:0]const u8, accent: rl.Color };

pub const games = [_]Game{
    .{ .title = "Game 1", .accent = rl.Color{ .r = 0, .g = 180, .b = 255, .a = 255 } },
    .{ .title = "Game 2", .accent = rl.Color{ .r = 255, .g = 130, .b = 0, .a = 255 } },
    .{ .title = "Game 3", .accent = rl.Color{ .r = 120, .g = 255, .b = 150, .a = 255 } },
    .{ .title = "Game 4", .accent = rl.Color{ .r = 60, .g = 125, .b = 75, .a = 255 } },
    .{ .title = "Game 5", .accent = rl.Color{ .r = 30, .g = 155, .b = 165, .a = 255 } },
    .{ .title = "Game 6", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
    .{ .title = "Game 7", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
    .{ .title = "Game 8", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
    .{ .title = "Game 9", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
    .{ .title = "Game 10", .accent = rl.Color{ .r = 90, .g = 25, .b = 175, .a = 255 } },
};
