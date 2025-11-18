const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const config = @import("config.zig");
const color_utils = @import("color.zig");
const Game = @import("game.zig").Game;
const calculateCardScale = @import("animation.zig").calculateCardScale;

/// Creates a supersampled gradient border render texture using the SDF shader in
/// gradient-border.fs. The shader renders a rounded gradient ring with a transparent
/// inner gap based on configuration:
/// - card_corner_roundness controls the curvature of card and border.
/// - gap_margin controls the empty space between card and border.
/// - outer_margin controls the visual thickness of the gradient ring.
pub fn createBorderTexture() !rl.RenderTexture {
    // Configuration
    const total_margin: f32 = config.gap_margin + config.outer_margin;
    const base_border_w: f32 = config.card_w + total_margin * 2.0;
    const base_border_h: f32 = config.card_h + total_margin * 2.0;

    // Super-sampled texture dimensions
    const border_w_i: i32 = @intFromFloat(base_border_w * config.ss_factor);
    const border_h_i: i32 = @intFromFloat(base_border_h * config.ss_factor);

    // 1. Load resources for SDF-based gradient border
    const border_rt = try rl.loadRenderTexture(border_w_i, border_h_i);
    rl.setTextureFilter(border_rt.texture, .bilinear);

    // Load SDF gradient-border shader from external file.
    // Path is relative to the executable's working directory
    const shader = try rl.loadShader(null, "src/gradient-border.fs");
    defer rl.unloadShader(shader);

    // 2. Prepare uniforms (use variables to ensure correct pointers)
    const width_f = @as(f32, @floatFromInt(border_w_i));
    const height_f = @as(f32, @floatFromInt(border_h_i));

    const card_radius = config.card_corner_roundness * config.card_w;

    // Use the same base radius as the main card so corner curvature matches visually.
    // Gap and border thickness are handled by expanding the rect and the SDF thickness,
    // not by inflating the radius itself.
    var radius_ss: f32 = card_radius * config.ss_factor;
    var border_thick_ss: f32 = config.outer_margin * config.ss_factor;
    var size_values = [2]f32{ width_f, height_f };

    // Normalize Colors
    var c_tl = rl.colorNormalize(color_utils.gradient_top);
    var c_tr = rl.colorNormalize(color_utils.gradient_top_right);
    var c_bl = rl.colorNormalize(color_utils.gradient_bottom_left);
    var c_br = rl.colorNormalize(color_utils.gradient_bottom_right);

    // 3. Render using the Shader
    rl.beginTextureMode(border_rt);
    rl.clearBackground(.blank);

    rl.beginShaderMode(shader);

    // Set uniforms
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "rectSize"), &size_values, .vec2);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "radius"), &radius_ss, .float);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "borderThickness"), &border_thick_ss, .float);

    rl.setShaderValue(shader, rl.getShaderLocation(shader, "colTL"), &c_tl, .vec4);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "colTR"), &c_tr, .vec4);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "colBL"), &c_bl, .vec4);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "colBR"), &c_br, .vec4);

    // Draw simple white rect; shader handles the rest
    rl.drawRectangle(0, 0, border_w_i, border_h_i, .white);

    rl.endShaderMode();
    rl.endTextureMode();

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
fn calculateSpacingOffset(idx_f: f32, selected_index_f: f32, selected_extra_spacing: f32) f32 {
    const diff = idx_f - selected_index_f;

    if (diff <= -1.0) {
        return -selected_extra_spacing;
    } else if (diff >= 1.0) {
        return selected_extra_spacing;
    } else {
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

    const distance = @abs(idx_f - params.selected_index_f);
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

    // Draw gradient border ring for selected card
    if (is_selected) {
        drawGradientBorder(card_x, card_y, draw_w, draw_h, params.border_texture);
    }

    // Draw main card
    const game_rect = rl.Rectangle{ .x = card_x, .y = card_y, .width = draw_w, .height = draw_h };
    rl.drawRectangleRounded(
        game_rect,
        config.card_corner_roundness,
        64,
        card_color,
    );

    // Draw game title
    const text_size: i32 = @intFromFloat(params.card_w * 0.096);
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
    const texture_card_w: f32 = config.card_w;
    const texture_scale: f32 = draw_w / texture_card_w;

    // Visual sizes
    const gap_visual: f32 = config.gap_margin * texture_scale;
    const outer_visual: f32 = config.outer_margin * texture_scale;
    const total_offset: f32 = gap_visual + outer_visual;

    // Expand from card edge to include gap + border
    const dest = rl.Rectangle{
        .x = card_x - total_offset,
        .y = card_y - total_offset,
        .width = draw_w + (total_offset * 2.0),
        .height = draw_h + (total_offset * 2.0),
    };

    // Flip Y for FBO
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(border_texture.texture.width)),
        .height = -@as(f32, @floatFromInt(border_texture.texture.height)),
    };

    rl.drawTexturePro(border_texture.texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0.0, .white);
}
