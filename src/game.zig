const rl = @import("raylib");

pub const Game = struct { title: [:0]const u8, accent: rl.Color };

pub const games = [_]Game{
    .{ .title = "Game 1", .accent = rl.Color{ .r = 0, .g = 180, .b = 255, .a = 255 } },
    .{ .title = "Game 2", .accent = rl.Color{ .r = 255, .g = 130, .b = 0, .a = 255 } },
    .{ .title = "Game 3", .accent = rl.Color{ .r = 120, .g = 255, .b = 150, .a = 255 } },
    .{ .title = "Game 4", .accent = rl.Color{ .r = 60, .g = 125, .b = 75, .a = 255 } },
};
