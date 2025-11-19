const rl = @import("raylib");

/// Scales a color channel by a factor, clamping to 0-255 range
fn scaleChannel(channel: u8, factor: f32) u8 {
    const f = @as(f32, @floatFromInt(channel)) * factor;
    const clamped = if (f > 255.0) 255.0 else f;
    return @intFromFloat(clamped);
}

/// Darkens a color by multiplying each RGB channel by a factor
pub fn darkenColor(c: rl.Color, factor: f32) rl.Color {
    return rl.Color{
        .r = scaleChannel(c.r, factor),
        .g = scaleChannel(c.g, factor),
        .b = scaleChannel(c.b, factor),
        .a = c.a,
    };
}

// Gradient colors for the card border effect
pub const gradient_top = rl.Color{ .r = 40, .g = 40, .b = 50, .a = 200 }; // gray / transparent
pub const gradient_top_right = rl.Color{ .r = 60, .g = 60, .b = 70, .a = 200 };
pub const gradient_bottom_left = rl.Color{ .r = 235, .g = 190, .b = 120, .a = 250 }; // warm gold
pub const gradient_bottom_right = rl.Color{ .r = 180, .g = 120, .b = 255, .a = 250 }; // purple
