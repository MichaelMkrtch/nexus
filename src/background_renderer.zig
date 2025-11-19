const std = @import("std");
const rl = @import("raylib");
const Game = @import("game.zig").Game;

pub const BackgroundState = struct {
    current_index: ?usize,
    previous_index: ?usize,
    transition_progress: f32, // 0.0 = showing previous, 1.0 = showing current
    transition_speed: f32,

    pub fn init() BackgroundState {
        return .{
            .current_index = null,
            .previous_index = null,
            .transition_progress = 1.0,
            .transition_speed = 1.1, // Higher = faster
        };
    }

    /// Updates the background when selection changes
    pub fn updateSelection(self: *BackgroundState, selected_index: usize) void {
        // If this is the same game, do nothing
        if (self.current_index) |idx| {
            if (idx == selected_index) return;
        }

        // Move current to previous
        self.previous_index = self.current_index;
        self.current_index = selected_index;
        self.transition_progress = 0.0; // Start transition
    }

    /// Updates transition animation
    pub fn update(self: *BackgroundState, dt: f32) void {
        if (self.transition_progress < 1.0) {
            self.transition_progress += dt * self.transition_speed;
            if (self.transition_progress > 1.0) {
                self.transition_progress = 1.0;
                // Clear previous index after transition completes
                self.previous_index = null;
            }
        }
    }

    /// Renders the background with crossfade effect using pre-cached textures
    pub fn render(self: *BackgroundState, screen_w: i32, screen_h: i32, hero_textures: []const ?rl.Texture2D) void {
        const screen_w_f: f32 = @floatFromInt(screen_w);
        const screen_h_f: f32 = @floatFromInt(screen_h);

        // Render previous texture (fading out)
        if (self.previous_index) |prev_idx| {
            if (prev_idx < hero_textures.len) {
                if (hero_textures[prev_idx]) |prev_tex| {
                    const prev_alpha: u8 = @intFromFloat((1.0 - self.transition_progress) * 255.0);
                    renderHeroTexture(prev_tex, screen_w_f, screen_h_f, prev_alpha);
                }
            }
        }

        // Render current texture (fading in)
        if (self.current_index) |curr_idx| {
            if (curr_idx < hero_textures.len) {
                if (hero_textures[curr_idx]) |curr_tex| {
                    const curr_alpha: u8 = @intFromFloat(self.transition_progress * 255.0);
                    renderHeroTexture(curr_tex, screen_w_f, screen_h_f, curr_alpha);
                }
            }
        }
    }
};

/// Renders a hero texture scaled to cover the screen with darkening overlay
fn renderHeroTexture(texture: rl.Texture2D, screen_w: f32, screen_h: f32, alpha: u8) void {
    const tex_w: f32 = @floatFromInt(texture.width);
    const tex_h: f32 = @floatFromInt(texture.height);
    const tex_aspect = tex_w / tex_h;
    const screen_aspect = screen_w / screen_h;

    // Calculate dimensions to cover screen (similar to CSS background-size: cover)
    var final_w: f32 = screen_w;
    var final_h: f32 = screen_h;

    if (tex_aspect > screen_aspect) {
        // Texture is wider - scale by height
        final_h = screen_h;
        final_w = screen_h * tex_aspect;
    } else {
        // Texture is taller - scale by width
        final_w = screen_w;
        final_h = screen_w / tex_aspect;
    }

    const offset_x = (screen_w - final_w) / 2.0;
    const offset_y = (screen_h - final_h) / 2.0;

    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = tex_w,
        .height = tex_h,
    };

    const dest = rl.Rectangle{
        .x = offset_x,
        .y = offset_y,
        .width = final_w,
        .height = final_h,
    };

    // Draw texture with alpha
    rl.drawTexturePro(
        texture,
        src,
        dest,
        rl.Vector2{ .x = 0, .y = 0 },
        0.0,
        rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha },
    );

    // Draw darkening overlay to make foreground content readable
    const overlay_alpha: u8 = @intFromFloat(@as(f32, @floatFromInt(alpha)) * 0.6); // 60% darkness
    rl.drawRectangle(
        0,
        0,
        @intFromFloat(screen_w),
        @intFromFloat(screen_h),
        rl.Color{ .r = 0, .g = 0, .b = 0, .a = overlay_alpha },
    );
}
