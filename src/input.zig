const std = @import("std");
const rl = @import("raylib");

const leftStickDeadzoneX: f32 = 0.6;
const leftStickDeadzoneY: f32 = 0.6;
const rightStickDeadzoneX: f32 = 0.6;
const rightStickDeadzoneY: f32 = 0.6;
const leftTriggerDeadzone: f32 = -0.9;
const rightTriggerDeadzone: f32 = -0.9;

var gamepad: i32 = 0;

pub const InputState = struct {
    hold_timer: f32,
    repeat_timer: f32,
    initial_delay: f32 = 0.4, // delay before continuous scroll starts
    repeat_rate: f32 = 0.08, // time between repeats when holding
    stick_right_was_active: bool = false, // track stick state for edge detection
    stick_left_was_active: bool = false,

    pub fn init() InputState {
        return .{ .hold_timer = 0, .repeat_timer = 0, .stick_right_was_active = false, .stick_left_was_active = false };
    }
};

/// Checks if the user has confirmed their selection
pub fn isSelectionConfirmed() bool {
    return rl.isKeyPressed(.enter);
}

/// Helper to get left stick X position with deadzone applied
fn getLeftStickX() f32 {
    if (!rl.isGamepadAvailable(gamepad)) return 0;
    const stick_x = rl.getGamepadAxisMovement(gamepad, .left_x);
    // Apply deadzone - return 0 if within deadzone
    if (@abs(stick_x) < leftStickDeadzoneX) return 0;
    return stick_x;
}

/// Helper to check if right input is pressed (keyboard, gamepad button, or stick just pushed)
fn isRightPressed(state: *const InputState) bool {
    const keyboard_right = rl.isKeyPressed(.right);
    const gamepad_right = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonPressed(gamepad, .left_face_right);

    // Stick "pressed" = stick is now beyond deadzone AND wasn't active last frame
    const stick_x = getLeftStickX();
    const stick_is_right = stick_x > leftStickDeadzoneX;
    const stick_right = stick_is_right and !state.stick_right_was_active;

    return keyboard_right or gamepad_right or stick_right;
}

/// Helper to check if left input is pressed (keyboard, gamepad button, or stick just pushed)
fn isLeftPressed(state: *const InputState) bool {
    const keyboard_left = rl.isKeyPressed(.left);
    const gamepad_left = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonPressed(gamepad, .left_face_left);

    // Stick "pressed" = stick is now beyond deadzone AND wasn't active last frame
    const stick_x = getLeftStickX();
    const stick_is_left = stick_x < -leftStickDeadzoneX;
    const stick_left = stick_is_left and !state.stick_left_was_active;

    return keyboard_left or gamepad_left or stick_left;
}

/// Helper to check if right input is held down (keyboard, gamepad button, or stick position)
fn isRightDown() bool {
    const keyboard_right = rl.isKeyDown(.right);
    const gamepad_right = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonDown(gamepad, .left_face_right);
    const stick_x = getLeftStickX();
    const stick_right = stick_x > leftStickDeadzoneX;

    return keyboard_right or gamepad_right or stick_right;
}

/// Helper to check if left input is held down (keyboard, gamepad button, or stick position)
fn isLeftDown() bool {
    const keyboard_left = rl.isKeyDown(.left);
    const gamepad_left = rl.isGamepadAvailable(gamepad) and rl.isGamepadButtonDown(gamepad, .left_face_left);
    const stick_x = getLeftStickX();
    const stick_left = stick_x < -leftStickDeadzoneX;

    return keyboard_left or gamepad_left or stick_left;
}

/// Handles input for game selection navigation with continuous scrolling
/// Supports keyboard, gamepad buttons, and left analog stick X-axis
/// Returns the new selected index based on input
pub fn handleSelectionInput(current_index: usize, total_items: usize, state: *InputState, dt: f32) usize {
    var new_index = current_index;

    // Check for initial input press (immediate response)
    if (isRightPressed(state)) {
        new_index = (current_index + 1) % total_items;
        state.hold_timer = 0;
        state.repeat_timer = 0;
    } else if (isLeftPressed(state)) {
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

    // Update stick state for next frame's edge detection
    const stick_x = getLeftStickX();
    state.stick_right_was_active = stick_x > leftStickDeadzoneX;
    state.stick_left_was_active = stick_x < -leftStickDeadzoneX;

    return new_index;
}
