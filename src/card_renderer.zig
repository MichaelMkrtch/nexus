const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const config = @import("config.zig");
const color_utils = @import("color.zig");
const Game = @import("game.zig").Game;
const calculateCardScale = @import("animation.zig").calculateCardScale;

/// Creates a supersampled gradient border render texture
pub fn createBorderTexture() !rl.RenderTexture {
    // Build a rounded gradient ring texture for a base card size.
    // Ring geometry is driven by config.gap_margin (gap) and config.outer_margin (border thickness).
    const total_margin: f32 = config.gap_margin + config.outer_margin;
    const base_border_w: f32 = config.card_w + total_margin * 2.0;
    const base_border_h: f32 = config.card_h + total_margin * 2.0;

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

        // Compute rounded corner radii so that card, gap, and border
        // follow the padding rounding rule:
        //  - Start from the card radius
        //  - Inner ring radius = card radius + gap
        //  - Outer ring radius = card radius + gap + border thickness
        const card_roundness: f32 = 0.25;
        const card_radius: f32 = card_roundness * config.card_w;
        const gap: f32 = config.gap_margin;
        const outer: f32 = config.outer_margin;

        const radius_inner: f32 = card_radius + gap;
        const radius_outer: f32 = card_radius + gap + outer;

        const inner_width: f32 = config.card_w + gap * 2.0;
        const outer_width: f32 = config.card_w + (gap + outer) * 2.0;

        const inner_roundness: f32 = radius_inner / inner_width;
        const outer_roundness: f32 = radius_outer / outer_width;

        // 1. Draw a solid white rounded rect as a mask (outer ring radius)
        rl.drawRectangleRounded(rect, outer_roundness, 32, .white);

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

        // 3. Cut out the inner area (card + gap) to create a transparent hole
        const inner_margin_ss = config.outer_margin * config.ss_factor;
        const inner_rect = rl.Rectangle{
            .x = inner_margin_ss,
            .y = inner_margin_ss,
            .width = rect.width - inner_margin_ss * 2.0,
            .height = rect.height - inner_margin_ss * 2.0,
        };

        // Use subtract_colors with transparent black to clear color + alpha
        rl.beginBlendMode(.subtract_colors);
        rl.drawRectangleRounded(inner_rect, inner_roundness, 32, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
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

    // Draw gradient border ring for selected card (ring texture already has transparent center)
    if (is_selected) {
        drawGradientBorder(card_x, card_y, draw_w, draw_h, params.border_texture);
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
fn drawGradientBorder(card_x: f32, card_y: f32, draw_w: f32, draw_h: f32, border_texture: rl.RenderTexture) void {
    // Scale border + gap relative to the base config card size
    const texture_card_w: f32 = config.card_w;
    const texture_scale: f32 = draw_w / texture_card_w;

    const gap_visual: f32 = config.gap_margin * texture_scale;
    const outer_visual: f32 = config.outer_margin * texture_scale;
    const total_visual: f32 = gap_visual + outer_visual;

    // Destination rectangle: card plus gap plus border thickness
    const dest = rl.Rectangle{
        .x = card_x - total_visual,
        .y = card_y - total_visual,
        .width = draw_w + total_visual * 2.0,
        .height = draw_h + total_visual * 2.0,
    };

    // src uses full supersampled texture; hole already baked in
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(border_texture.texture.width)),
        .height = -@as(f32, @floatFromInt(border_texture.texture.height)),
    };

    rl.drawTexturePro(border_texture.texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0.0, .white);
}
