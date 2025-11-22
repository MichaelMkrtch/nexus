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
const background_renderer = @import("background_renderer.zig");

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

    // Create texture caches
    const textures = try allocator.alloc(card_renderer.TextureEntry, games.len);
    defer {
        // unload textures
        for (textures) |entry| {
            if (entry.loaded) rl.unloadTexture(entry.texture);
        }
        allocator.free(textures);
    }

    for (textures) |*e| e.* = .{ .loaded = false };

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

    // Create hero texture cache and pre-load all hero images (after window init)
    const hero_textures = try allocator.alloc(?rl.Texture2D, games.len);
    defer {
        for (hero_textures) |tex_opt| {
            if (tex_opt) |tex| rl.unloadTexture(tex);
        }
        allocator.free(hero_textures);
    }

    for (games, 0..) |game, i| {
        if (game.hero_image_path) |path| {
            const texture = rl.loadTexture(path) catch |err| {
                std.log.warn("Failed to load hero texture for {s}: {s}", .{
                    path,
                    @errorName(err),
                });
                hero_textures[i] = null;
                continue;
            };

            // Enable filtering for smooth scaling
            var tex = texture;
            rl.genTextureMipmaps(&tex);
            rl.setTextureFilter(tex, .trilinear);
            hero_textures[i] = tex;
        } else {
            hero_textures[i] = null;
        }
    }

    // ---------------- State ----------------
    var selected_index: usize = 0;
    var selected_index_f: f32 = 0.0; // animated version of selected_index
    var input_state = input.InputState.init();

    // Background transition delay state
    var selection_hold_timer: f32 = 0.0;
    var pending_bg_index: ?usize = 0; // Start with first game as pending
    const bg_transition_delay: f32 = 0.5;

    // Initialize background renderer with first game
    var bg_state = background_renderer.BackgroundState.init();
    bg_state.updateSelection(selected_index);

    // --- Create border render texture (one-time) ---
    const border_rt = try card_renderer.createBorderTexture();
    defer rl.unloadRenderTexture(border_rt);

    // --- Load rounded corner shader (one-time) ---
    const rounded_shader = try rl.loadShader(null, "src/rounded-texture.fs");
    defer rl.unloadShader(rounded_shader);

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
        const prev_selected_index = selected_index;
        selected_index = input.handleSelectionInput(selected_index, games.len, &input_state, dt);

        const selected_game = games[selected_index];

        // Handle background transition with delay to prevent flashing during fast scrolling
        if (selected_index != prev_selected_index) {
            // Selection changed - reset timer and update pending index
            selection_hold_timer = 0.0;
            pending_bg_index = selected_index;
        } else if (pending_bg_index) |pending_idx| {
            // Selection hasn't changed - increment timer
            selection_hold_timer += dt;

            // After delay, update background
            if (selection_hold_timer >= bg_transition_delay) {
                bg_state.updateSelection(pending_idx);
                pending_bg_index = null; // Clear pending once applied
            }
        }

        // Update background transition animation
        bg_state.update(dt);

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

        // Clear with black first (fallback if no hero image)
        rl.clearBackground(rl.Color.black);

        // Render animated background with hero images
        bg_state.render(screen_w, screen_h, hero_textures);

        // Calculate responsive positioning and sizing
        const screen_h_f: f32 = @as(f32, @floatFromInt(screen_h));

        const card_size: f32 = screen_h_f * config.card_screen_height_ratio;
        const card_w = card_size;
        const card_h = card_size;

        // Position cards at top of screen below text
        const top_margin: f32 = 220.0; // Space below the title text
        const center_y: f32 = top_margin + card_h / 2.0;

        // Calculate spacing for carousel
        const base_spacing: f32 = card_size * config.card_spacing_ratio;
        const selected_extra_spacing: f32 = card_size * config.selected_spacing_ratio;

        // Anchor point starts at left edge, carousel scrolls horizontally
        // When first card is selected, it appears at the left margin
        const left_margin: f32 = 60.0;
        const selected_card_position: f32 = left_margin + card_w / 2.0;
        const center_x: f32 = selected_card_position + (selected_index_f * base_spacing);

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
                .texture_entry = &textures[i],
                .index = i,
                .selected_index = selected_index,
                .selected_index_f = selected_index_f,
                .border_texture = border_rt,
                .rounded_shader = rounded_shader,
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
