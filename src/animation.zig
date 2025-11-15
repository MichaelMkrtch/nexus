const std = @import("std");
const math = std.math;
const config = @import("config.zig");

/// Updates an animated float value to smoothly approach a target value
/// Uses exponential easing for smooth motion
pub fn updateAnimatedValue(current: f32, target: f32, dt: f32, speed: f32) f32 {
    const step = math.clamp(speed * dt, 0.0, 1.0);
    return current + (target - current) * step;
}

/// Calculates the scale factor for a card based on its distance from the selected index
/// Returns a value between base_scale and selected_scale
pub fn calculateCardScale(distance: f32) f32 {
    // 0 when centered, 1 when one step away or more
    const t = math.clamp(1.0 - distance, 0.0, 1.0);

    // scales between base and selected based on t
    return config.base_scale + (config.selected_scale - config.base_scale) * t;
}
