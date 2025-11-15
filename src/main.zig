const std = @import("std");
const nexus = @import("nexus");
const rl = @import("raylib");
const games = @import("game.zig").games;
const config = @import("config.zig");
const color_utils = @import("color.zig");
const animation = @import("animation.zig");
const input = @import("input.zig");
const card_renderer = @import("card_renderer.zig");

pub fn main() !void {
    rl.setConfigFlags(.{
        .msaa_4x_hint = true,
        .window_highdpi = true,
        .window_maximized = true,
        // .window_undecorated = true, // removes top bar and window controls
    });

    rl.initWindow(config.screen_w, config.screen_h, "Nexus");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // ---------------- State ----------------
    var selected_index: usize = 0;
    var selected_index_f: f32 = 0.0; // animated version of selected_index

    // --- Create border render texture (one-time) ---
    const border_rt = try card_renderer.createBorderTexture();
    defer rl.unloadRenderTexture(border_rt);

    // ---------------- Main Loop ----------------
    while (!rl.windowShouldClose()) {
        // Handle input
        selected_index = input.handleSelectionInput(selected_index, games.len);

        if (input.isSelectionConfirmed()) {
            const selected_game = games[selected_index];
            std.debug.print("You selected: {s}\n", .{selected_game.title});
        }

        // --- Animate selected_index_f toward selected_index ---
        const dt: f32 = rl.getFrameTime();
        const target: f32 = @as(f32, @floatFromInt(selected_index));
        selected_index_f = animation.updateAnimatedValue(selected_index_f, target, dt, config.lerp_speed);

        // ---------------- Draw ----------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        // Use selected game's accent for the background
        const selected_game = games[selected_index];
        const bg_color = color_utils.darkenColor(selected_game.accent, 0.35);
        rl.drawRectangle(0, 0, config.screen_w, config.screen_h, bg_color);

        rl.drawText("Nexus", 40, 40, 40, .white);
        rl.drawText(
            selected_game.title,
            40,
            80,
            24,
            .white,
        );

        // Render all game cards
        for (games, 0..) |game, i| {
            card_renderer.renderCard(.{
                .game = game,
                .index = i,
                .selected_index = selected_index,
                .selected_index_f = selected_index_f,
                .border_texture = border_rt,
            });
        }
    }
}
