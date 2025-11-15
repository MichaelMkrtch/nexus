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
        .window_resizable = true,
    });

    // Initialize with a larger default size
    rl.initWindow(1920, 1080, "Nexus");
    defer rl.closeWindow();

    // Maximize window after initialization
    rl.maximizeWindow();

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

        // Get current screen dimensions (handles resizing)
        const screen_w = rl.getScreenWidth();
        const screen_h = rl.getScreenHeight();

        // Use selected game's accent for the background
        const selected_game = games[selected_index];
        const bg_color = color_utils.darkenColor(selected_game.accent, 0.35);
        rl.clearBackground(bg_color);

        // Calculate responsive positioning and sizing
        const center_x: f32 = @as(f32, @floatFromInt(screen_w)) / 2.0;
        const center_y: f32 = @as(f32, @floatFromInt(screen_h)) / 2.0;

        // Scale card size based on screen height (40% of screen height)
        const screen_h_f: f32 = @as(f32, @floatFromInt(screen_h));
        const card_size: f32 = screen_h_f * 0.25;
        const card_w = card_size;
        const card_h = card_size;

        // Calculate spacing for carousel (selected card centered)
        const base_spacing: f32 = card_size - 5; // Small gap between cards
        const selected_extra_spacing: f32 = card_size * 0.2; // Extra space around selected

        // Draw title text at top
        rl.drawText("Games", 60, 60, 48, .white);
        rl.drawText(
            selected_game.title,
            60,
            120,
            28,
            .white,
        );

        // Render all game cards (carousel centered on selected card)
        for (games, 0..) |game, i| {
            card_renderer.renderCard(.{
                .game = game,
                .index = i,
                .selected_index = selected_index,
                .selected_index_f = selected_index_f,
                .border_texture = border_rt,
                .center_x = center_x,
                .center_y = center_y,
                .card_w = card_w,
                .card_h = card_h,
                .base_spacing = base_spacing,
                .selected_extra_spacing = selected_extra_spacing,
            });
        }
    }
}
