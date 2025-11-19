const std = @import("std");
const nexus = @import("nexus");
const rl = @import("raylib");
const steam_local = @import("steam/steam_local.zig");
const game_module = @import("game.zig");
const config = @import("config.zig");
const color_utils = @import("color.zig");
const animation = @import("animation.zig");
const input = @import("input.zig");
const card_renderer = @import("card_renderer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // 1. Load Steam Games
    const lists = steam_local.getInstalledGames(allocator) catch |err| {
        std.debug.print("Error: Failed to load games: {s}\n", .{@errorName(err)});
        return;
    };
    defer steam_local.freeGameLists(allocator, lists);

    const games = try game_module.buildUIGamesFromSteam(allocator, lists.games);
    defer game_module.freeUIGames(allocator, games);

    if (games.len == 0 and lists.games_without_exe.len == 0) {
        std.debug.print("No installed Steam games detected.\n", .{});
        return;
    }

    // 2. Init Raylib
    rl.setConfigFlags(.{
        .msaa_4x_hint = true,
        .window_highdpi = true,
        .window_resizable = true,
    });

    rl.initWindow(1920, 1080, "Nexus");
    defer rl.closeWindow();

    rl.setTargetFPS(120);

    // Maximize window after initialization
    rl.maximizeWindow();

    // ---------------- State ----------------
    var selected_index: usize = 0;
    var selected_index_f: f32 = 0.0; // animated version of selected_index
    var input_state = input.InputState.init();

    // --- Create border render texture (one-time) ---
    const border_rt = try card_renderer.createBorderTexture();
    defer rl.unloadRenderTexture(border_rt);

    // ---------------- Main Loop ----------------
    while (!rl.windowShouldClose()) {
        // Get delta time
        const dt: f32 = rl.getFrameTime();

        // convert []u8 to sentinel
        // // Should not happen
        // if (games.len == 0) {
        //     rl.beginDrawing();
        //     defer rl.endDrawing();

        //     rl.clearBackground(.black);
        //     rl.drawText("No Steam games with resolved executables.", 60, 60, 32, .white);

        //     if (lists.games_without_exe.len > 0) {
        //         var buf: [128]u8 = undefined;
        //         const msg = std.fmt.bufPrint(
        //             &buf,
        //             "{d} game(s) without resolved .exe",
        //             .{lists.games_without_exe.len},
        //         ) catch "error";

        //         rl.drawText(msg, 60, 110, 20, .gray);
        //     }

        //     continue;
        // }

        // Handle input with continuous scrolling (supports both keyboard and gamepad)
        selected_index = input.handleSelectionInput(selected_index, games.len, &input_state, dt);

        const selected_game = games[selected_index];

        if (input.isSelectionConfirmed()) {
            // Map to Steam game
            const steam_index = selected_game.steam_index;
            if (steam_index < lists.games.len) {
                std.debug.print("Launching: {s} (Steam App ID: {d})\n", .{ selected_game.title, lists.games[steam_index].app_id });
                try steam_local.launchGame(allocator, &lists.games[steam_index]);
            } else {
                std.debug.print("Error: steam_index {d} out of bounds for Steam games len={d}\n", .{ steam_index, lists.games.len });
            }
        }

        // --- Animate selected_index_f toward selected_index ---
        const target: f32 = @as(f32, @floatFromInt(selected_index));
        selected_index_f = animation.updateAnimatedValue(selected_index_f, target, dt, config.lerp_speed);

        // ---------------- Draw ----------------
        rl.beginDrawing();
        defer rl.endDrawing();

        // Get current screen dimensions (handles resizing)
        const screen_w = rl.getScreenWidth();
        const screen_h = rl.getScreenHeight();

        // TODO: Use selected game's background image
        // const bg_color = color_utils.darkenColor(selected_game.accent, 0.35);
        const bg_color = rl.Color.black;
        rl.clearBackground(bg_color);

        // Calculate responsive positioning and sizing
        const center_x: f32 = @as(f32, @floatFromInt(screen_w)) / 2.0;
        const center_y: f32 = @as(f32, @floatFromInt(screen_h)) / 2.0;
        // Scale card size based on screen height (configurable ratio)
        const screen_h_f: f32 = @as(f32, @floatFromInt(screen_h));

        const card_size: f32 = screen_h_f * config.card_screen_height_ratio;
        const card_w = card_size;
        const card_h = card_size;

        // Calculate spacing for carousel (selected card centered)
        // Use config ratios so spacing scales with card size but stays relatively tight.
        const base_spacing: f32 = card_size * config.card_spacing_ratio;
        const selected_extra_spacing: f32 = card_size * config.selected_spacing_ratio;

        // Draw title text at top
        rl.drawText("Games", 60, 60, 48, .white);
        rl.drawText(
            selected_game.title,
            60,
            120,
            28,
            .white,
        );

        // convert []u8 to sentinel
        // if (lists.games_without_exe.len > 0) {
        //     var buf: [128]u8 = undefined;
        //     const msg = std.fmt.bufPrint(
        //         &buf,
        //         "{d} game(s) without resolved .exe",
        //         .{lists.games_without_exe.len},
        //     ) catch "error";
        //     rl.drawText(msg, 60, 160, 18, .gray);
        // }

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
