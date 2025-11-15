const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const config = @import("config.zig");
const color_utils = @import("color.zig");
const Game = @import("game.zig").Game;
const calculateCardScale = @import("animation.zig").calculateCardScale;

/// Creates a supersampled gradient border render texture
pub fn createBorderTexture() !rl.RenderTexture {
    const base_border_w: f32 = config.card_w + config.border_margin * 2.0;
    const base_border_h: f32 = config.card_h + config.border_margin * 2.0;

    const border_w_i: i32 = @intFromFloat(base_border_w * config.ss_factor);
    const border_h_i: i32 = @intFromFloat(base_border_h * config.ss_factor);

    const border_rt = try rl.loadRenderTexture(border_w_i, border_h_i);

    // Smooth sampling when scaling down
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
            color_utils.gradient_top, // top-left
            color_utils.gradient_bottom_left, // bottom-left
            color_utils.gradient_bottom_right, // bottom-right
            color_utils.gradient_top_right, // top-right
        );
        rl.endBlendMode();
    }

    return border_rt;
}

/// Parameters for rendering a single game card
pub const CardRenderParams = struct {
    game: Game,
    index: usize,
    selected_index: usize,
    selected_index_f: f32,
    border_texture: rl.RenderTexture,
    center_x: f32,
    center_y: f32,
    card_w: f32,
    card_h: f32,
    base_spacing: f32,
    selected_extra_spacing: f32,
};

/// Calculates the extra spacing offset for a card based on its position relative to the selected card
/// The selected card gets extra spacing on both its left and right sides
/// Smoothly blends during animation to maintain even spacing
fn calculateSpacingOffset(idx_f: f32, selected_index_f: f32, selected_extra_spacing: f32) f32 {
    const diff = idx_f - selected_index_f;

    // Cards fully to the left (distance > 1)
    if (diff <= -1.0) {
        return -selected_extra_spacing;
    }
    // Cards fully to the right (distance > 1)
    else if (diff >= 1.0) {
        return selected_extra_spacing;
    }
    // Cards in transition zone (within 1 card distance of selected)
    // Blend from 0 at selected position to full offset at distance 1
    else {
        return diff * selected_extra_spacing;
    }
}

/// Renders a single game card with border, background, and text
pub fn renderCard(params: CardRenderParams) void {
    const idx_f: f32 = @as(f32, @floatFromInt(params.index));
    const base_offset: f32 = (idx_f - params.selected_index_f) * params.base_spacing;
    const spacing_offset = calculateSpacingOffset(idx_f, params.selected_index_f, params.selected_extra_spacing);
    const x = params.center_x + base_offset + spacing_offset - params.card_w / 2.0;
    const y: f32 = params.center_y - params.card_h / 2.0;

    // distance from the animated selection
    const distance = @abs(idx_f - params.selected_index_f);

    // Calculate scale based on distance
    const scale: f32 = calculateCardScale(distance);

    const draw_w = params.card_w * scale;
    const draw_h = params.card_h * scale;

    const card_x = x + (params.card_w - draw_w) / 2.0;
    const card_y = y + (params.card_h - draw_h) / 2.0;

    const is_selected = (params.index == params.selected_index);

    const card_color: rl.Color = if (is_selected)
        params.game.accent
    else
        rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };

    // Draw gradient border for selected card
    if (is_selected) {
        drawGradientBorder(card_x, card_y, draw_w, draw_h, params.border_texture, params.card_w);
    }

    // Gap ring (paint over inner part of gradient with background)
    if (is_selected) {
        const gap_margin = params.card_w * 0.024; // proportional to card size
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

    // Draw main card
    const game_rect = rl.Rectangle{ .x = card_x, .y = card_y, .width = draw_w, .height = draw_h };
    rl.drawRectangleRounded(
        game_rect,
        0.25,
        32,
        card_color,
    );

    // Draw game title with responsive sizing
    const text_size: i32 = @intFromFloat(params.card_w * 0.096); // proportional to card size
    const text_padding: f32 = params.card_w * 0.08;
    const text_bottom_offset: f32 = params.card_w * 0.2;
    rl.drawText(
        params.game.title,
        @intFromFloat(card_x + text_padding),
        @intFromFloat(card_y + draw_h - text_bottom_offset),
        text_size,
        .white,
    );
}

/// Draws the gradient border using a prerendered texture
fn drawGradientBorder(card_x: f32, card_y: f32, draw_w: f32, draw_h: f32, border_texture: rl.RenderTexture, card_w: f32) void {
    const base_border_w: f32 = config.card_w + config.border_margin * 2.0;
    const base_border_h: f32 = config.card_h + config.border_margin * 2.0;

    const border_w_i: i32 = @intFromFloat(base_border_w * config.ss_factor);
    const border_h_i: i32 = @intFromFloat(base_border_h * config.ss_factor);

    // Calculate outer margin proportional to card size
    const outer_margin = card_w * 0.048; // proportional to card size

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

    rl.drawTexturePro(border_texture.texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0.0, .white);
}
