const std = @import("std");
const nexus = @import("nexus");
const rl = @import("raylib");
const games = @import("game.zig").games;

const math = std.math;

fn scaleChannel(channel: u8, factor: f32) u8 {
    const f = @as(f32, @floatFromInt(channel)) * factor;
    const clamped = if (f > 255.0) 255.0 else f;
    return @intFromFloat(clamped);
}

fn darkenColor(c: rl.Color, factor: f32) rl.Color {
    return rl.Color{
        .r = scaleChannel(c.r, factor),
        .g = scaleChannel(c.g, factor),
        .b = scaleChannel(c.b, factor),
        .a = c.a,
    };
}

const gradient_top = rl.Color{ .r = 40, .g = 40, .b = 50, .a = 0 }; // gray / transparent
const gradient_top_right = rl.Color{ .r = 60, .g = 60, .b = 70, .a = 80 };
const gradient_bottom_left = rl.Color{ .r = 235, .g = 190, .b = 120, .a = 250 }; // warm gold
const gradient_bottom_right = rl.Color{ .r = 180, .g = 120, .b = 255, .a = 250 }; // purple

pub fn main() !void {
    const screen_w = 1280;
    const screen_h = 720;

    rl.setConfigFlags(.{
        .msaa_4x_hint = true,
        .window_highdpi = true,
        .window_resizable = true,
        // .window_undecorated = true, // removes top bar and window controls
    });

    rl.initWindow(screen_w, screen_h, "Nexus");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // ---------------- State ----------------
    var selected_index: usize = 0;
    var selected_index_f: f32 = 0.0; // animated version of selected_index
    const card_w: f32 = 250;
    const card_h: f32 = 250;
    const spacing: f32 = 270;
    const center_x: f32 = @as(f32, @floatFromInt(screen_w)) / 2.0;
    const border_margin: f32 = 10.0;

    // --- Create border render texture (one-time) ---
    const ss_factor: f32 = 8.0;

    const base_border_w: f32 = card_w + border_margin * 2.0;
    const base_border_h: f32 = card_h + border_margin * 2.0;

    const border_w_i: i32 = @intFromFloat(base_border_w * ss_factor);
    const border_h_i: i32 = @intFromFloat(base_border_h * ss_factor);

    const border_rt = try rl.loadRenderTexture(border_w_i, border_h_i);
    defer rl.unloadRenderTexture(border_rt);

    // Crucial: smooth sampling when scaling down
    rl.setTextureFilter(border_rt.texture, .bilinear);

    // Draw rounded gradient into the render texture
    {
        rl.beginTextureMode(border_rt);
        defer rl.endTextureMode();

        rl.clearBackground(.blank);

        const rect = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(border_w_i)),
            .height = @as(f32, @floatFromInt(border_h_i)),
        };

        // 1. Draw a solid white rounded rect as a mask
        rl.drawRectangleRounded(
            rect,
            0.3, // outer border roundness
            64,
            .white,
        );

        // 2. Multiply in the 4-corner gradient, clipped by the rounded mask
        rl.beginBlendMode(.multiplied);
        rl.drawRectangleGradientEx(
            rect,
            gradient_top, // top-left
            gradient_bottom_left, // bottom-left
            gradient_bottom_right, // bottom-right
            gradient_top_right, // top-right
        );
        rl.endBlendMode();
    }

    // ---------------- Main Loop ----------------
    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.right)) {
            selected_index = (selected_index + 1) % games.len;
        }

        if (rl.isKeyPressed(.left)) {
            selected_index = if (selected_index == 0)
                games.len - 1
            else
                selected_index - 1;
        }

        if (rl.isKeyPressed(.enter)) {
            const selected_game = games[selected_index];
            std.debug.print("You selected: {s}\n", .{selected_game.title});
        }

        // --- Animate selected_index_f toward selected_index ---
        const dt: f32 = rl.getFrameTime();
        const target: f32 = @as(f32, @floatFromInt(selected_index));

        // how quickly it moves toward the target (tweakable)
        const lerp_speed: f32 = 8.0;

        // simple exponential-ish ease, clamped so it doesn't explode
        const step = math.clamp(lerp_speed * dt, 0.0, 1.0);
        selected_index_f += (target - selected_index_f) * step;

        // ---------------- Draw ----------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        // Use selected game's accent for the background
        const selected_game = games[selected_index];
        const bg_color = darkenColor(selected_game.accent, 0.35);
        rl.drawRectangle(0, 0, screen_w, screen_h, bg_color);

        rl.drawText("Nexus", 40, 40, 40, .white);
        rl.drawText(
            selected_game.title,
            40,
            80,
            24,
            .white,
        );

        for (games, 0..) |game, i| {
            const idx_f: f32 = @as(f32, @floatFromInt(i));
            const offset: f32 = (idx_f - selected_index_f) * spacing;
            const x = center_x + offset - card_w / 2.0;
            const y: f32 = 120;

            // distance from the animated selection
            const distance = @abs(idx_f - selected_index_f);

            // 0 when centered, 1 when one step away or more
            const t = math.clamp(1.0 - distance, 0.0, 1.0);

            // scales between base and selected based on t
            const base_scale: f32 = 0.9;
            const selected_scale: f32 = 1.1;
            const scale: f32 = base_scale + (selected_scale - base_scale) * t;

            const draw_w = card_w * scale;
            const draw_h = card_h * scale;

            const card_x = x + (card_w - draw_w) / 2.0;
            const card_y = y + (card_h - draw_h) / 2.0;

            const is_selected = (i == selected_index);

            const color: rl.Color = if (is_selected)
                game.accent
            else
                rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };

            const game_rect = rl.Rectangle{ .x = card_x, .y = card_y, .width = draw_w, .height = draw_h };

            const outer_margin: f32 = 12.0; // gradient border thickness
            const gap_margin: f32 = 6.0; // gap between border and card

            // Gradient border (using render texture)
            if (is_selected) {
                // dest uses base size (no *ss_factor)
                const dest = rl.Rectangle{
                    .x = card_x - outer_margin,
                    .y = card_y - outer_margin,
                    .width = draw_w + outer_margin * 2.0,
                    .height = draw_h + outer_margin * 2.0,
                };

                // src uses full supersampled texture
                const src = rl.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @as(f32, @floatFromInt(border_w_i)),
                    .height = -@as(f32, @floatFromInt(border_h_i)),
                };

                rl.drawTexturePro(border_rt.texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0.0, .white);
            }

            // Gap ring (paint over inner part of gradient with background)
            if (is_selected) {
                rl.drawRectangleRounded(
                    rl.Rectangle{
                        .x = card_x - gap_margin,
                        .y = card_y - gap_margin,
                        .width = draw_w + gap_margin * 2.0,
                        .height = draw_h + gap_margin * 2.0,
                    },
                    0.28,
                    32,
                    rl.Color{ .r = 20, .g = 20, .b = 20, .a = 255 },
                );
            }

            rl.drawRectangleRounded(
                game_rect,
                0.25,
                32,
                color,
            );

            rl.drawText(
                game.title,
                @intFromFloat(card_x + 20),
                @intFromFloat(card_y + draw_h - 50),
                24,
                .white,
            );
        }
    }
}
