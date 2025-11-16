const std = @import("std");
const rl = @import("raylib");

const leftStickDeadzoneX: f16 = 0.1;
const leftStickDeadzoneY: f16 = 0.1;
const rightStickDeadzoneX: f16 = 0.1;
const rightStickDeadzoneY: f16 = 0.1;
const leftTriggerDeadzone: f16 = -0.9;
const rightTriggerDeadzone: f16 = -0.9;

var gamepad: i32 = 0;

pub const InputState = struct {
    hold_timer: f32,
    repeat_timer: f32,
    initial_delay: f32 = 0.4, // delay before continuous scroll starts
    repeat_rate: f32 = 0.08, // time between repeats when holding

    pub fn init() InputState {
        return .{ .hold_timer = 0, .repeat_timer = 0 };
    }
};

/// Checks if the user has confirmed their selection
pub fn isSelectionConfirmed() bool {
    return rl.isKeyPressed(.enter);
}

/// Helper to check if right input is pressed (keyboard or gamepad)
fn isRightPressed() bool {
    const keyboard_right = rl.isKeyPressed(.right);
    const gamepad_right = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonPressed(gamepad, .left_face_right);
    return keyboard_right or gamepad_right;
}

/// Helper to check if left input is pressed (keyboard or gamepad)
fn isLeftPressed() bool {
    const keyboard_left = rl.isKeyPressed(.left);
    const gamepad_left = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonPressed(gamepad, .left_face_left);
    return keyboard_left or gamepad_left;
}

/// Helper to check if right input is held down (keyboard or gamepad)
fn isRightDown() bool {
    const keyboard_right = rl.isKeyDown(.right);
    const gamepad_right = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonDown(gamepad, .left_face_right);
    return keyboard_right or gamepad_right;
}

/// Helper to check if left input is held down (keyboard or gamepad)
fn isLeftDown() bool {
    const keyboard_left = rl.isKeyDown(.left);
    const gamepad_left = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonDown(gamepad, .left_face_left);
    return keyboard_left or gamepad_left;
}

/// Handles input for game selection navigation with continuous scrolling
/// Supports both keyboard and gamepad input
/// Returns the new selected index based on input
pub fn handleSelectionInput(current_index: usize, total_items: usize, state: *InputState, dt: f32) usize {
    var new_index = current_index;

    // Check for initial input press (immediate response)
    if (isRightPressed()) {
        new_index = (current_index + 1) % total_items;
        state.hold_timer = 0;
        state.repeat_timer = 0;
    } else if (isLeftPressed()) {
        new_index = if (current_index == 0)
            total_items - 1
        else
            current_index - 1;
        state.hold_timer = 0;
        state.repeat_timer = 0;
    }
    // Handle continuous scrolling when held
    else if (isRightDown()) {
        state.hold_timer += dt;

        // After initial delay, start repeating
        if (state.hold_timer >= state.initial_delay) {
            state.repeat_timer += dt;

            if (state.repeat_timer >= state.repeat_rate) {
                new_index = (current_index + 1) % total_items;
                state.repeat_timer = 0; // Reset repeat timer for next repeat
            }
        }
    } else if (isLeftDown()) {
        state.hold_timer += dt;

        // After initial delay, start repeating
        if (state.hold_timer >= state.initial_delay) {
            state.repeat_timer += dt;

            if (state.repeat_timer >= state.repeat_rate) {
                new_index = if (current_index == 0)
                    total_items - 1
                else
                    current_index - 1;
                state.repeat_timer = 0; // Reset repeat timer for next repeat
            }
        }
    } else {
        // No input held - reset timers
        state.hold_timer = 0;
        state.repeat_timer = 0;
    }

    return new_index;
}
