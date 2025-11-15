// Application configuration and constants

// Window settings
pub const screen_w: i32 = 1280;
pub const screen_h: i32 = 720;

// Card dimensions and layout
pub const card_w: f32 = 250;
pub const card_h: f32 = 250;
pub const spacing: f32 = 270;
pub const center_x: f32 = @as(f32, @floatFromInt(screen_w)) / 2.0;

// Border settings
pub const border_margin: f32 = 10.0;
pub const outer_margin: f32 = 12.0; // gradient border thickness
pub const gap_margin: f32 = 6.0; // gap between border and card

// Border supersampling factor for smooth gradients
pub const ss_factor: f32 = 8.0;

// Animation settings
pub const lerp_speed: f32 = 8.0;

// Card scaling
pub const base_scale: f32 = 0.9;
pub const selected_scale: f32 = 1.1;
