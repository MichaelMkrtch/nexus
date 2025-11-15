// Application configuration and constants

// Window settings
pub const screen_w: i32 = 1280;
pub const screen_h: i32 = 720;

// Card dimensions and layout
pub const card_w: f32 = 250;
pub const card_h: f32 = 250;
pub const base_spacing: f32 = 240; // spacing between non-selected cards
pub const selected_extra_spacing: f32 = 50; // extra space on each side of selected card
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
