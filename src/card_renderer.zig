const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const config = @import("config.zig");
const color_utils = @import("color.zig");
const Game = @import("game.zig").Game;
const calculateCardScale = @import("animation.zig").calculateCardScale;

pub const TextureEntry = struct { loaded: bool, texture: rl.Texture2D = undefined };

pub fn ensureCardTexture(game: Game, tex_entry: *TextureEntry) void {
    if (tex_entry.loaded) return;

    if (game.cover_image_path) |path| {
        tex_entry.texture = rl.loadTexture(path) catch |err| {
            std.log.warn("Failed to load texture for {s}: {s}", .{
                path,
                @errorName(err),
            });
            return; // leave loaded = false
        };

        tex_entry.loaded = true;
    }
}

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
    texture_entry: *TextureEntry,
    index: usize,
    selected_index: usize,
    selected_index_f: f32,
    border_texture: rl.RenderTexture,
    rounded_shader: rl.Shader,
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

    // 1) Border first so it sits "around" the card
    if (is_selected) {
        drawGradientBorder(card_x, card_y, draw_w, draw_h, params.border_texture);
    }

    // 2) Card background (under art)
    const game_rect = rl.Rectangle{
        .x = card_x,
        .y = card_y,
        .width = draw_w,
        .height = draw_h,
    };

    // You can tweak this to use a game-specific accent color later
    const card_bg_color = rl.Color{
        .r = 20,
        .g = 20,
        .b = 25,
        .a = 255,
    };

    rl.drawRectangleRounded(
        game_rect,
        config.card_corner_roundness,
        64,
        card_bg_color,
    );

    // 3) Cover art (if available), scaled to fit within the rounded card
    ensureCardTexture(params.game, params.texture_entry);

    if (params.texture_entry.loaded) {
        const tex = params.texture_entry.texture;

        const tex_w: f32 = @floatFromInt(tex.width);
        const tex_h: f32 = @floatFromInt(tex.height);
        const tex_aspect = tex_w / tex_h;
        const card_aspect = draw_w / draw_h;

        var final_w = draw_w;
        var final_h = draw_h;

        if (tex_aspect > card_aspect) {
            // Texture is wider than card → scale by height to cover
            final_h = draw_h;
            final_w = draw_h * tex_aspect;
        } else {
            // Texture is taller than card → scale by width to cover
            final_w = draw_w;
            final_h = draw_w / tex_aspect;
        }

        const offset_x = (draw_w - final_w) / 2.0;
        const offset_y = (draw_h - final_h) / 2.0;

        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = tex_w,
            .height = tex_h,
        };

        const dest = rl.Rectangle{
            .x = card_x + offset_x,
            .y = card_y + offset_y,
            .width = final_w,
            .height = final_h,
        };

        // Apply rounded corner shader
        rl.beginShaderMode(params.rounded_shader);

        // Set shader uniforms
        var size_values = [2]f32{ draw_w, draw_h };
        // Match raylib's drawRectangleRounded calculation exactly
        // raylib uses: radius = min(width, height) * roundness / 2.0
        const min_dim = @min(draw_w, draw_h);
        var radius_value: f32 = min_dim * config.card_corner_roundness / 2.0;

        rl.setShaderValue(
            params.rounded_shader,
            rl.getShaderLocation(params.rounded_shader, "rectSize"),
            &size_values,
            .vec2,
        );
        rl.setShaderValue(
            params.rounded_shader,
            rl.getShaderLocation(params.rounded_shader, "radius"),
            &radius_value,
            .float,
        );

        rl.drawTexturePro(
            tex,
            src,
            dest,
            rl.Vector2{ .x = 0, .y = 0 },
            0.0,
            .white,
        );

        rl.endShaderMode();
    }
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
