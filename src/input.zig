const rl = @import("raylib");

pub const InputState = struct {
    hold_timer: f32,
    repeat_timer: f32,
    initial_delay: f32 = 0.4, // delay before continuous scroll starts
    repeat_rate: f32 = 0.08, // time between repeats when holding

    pub fn init() InputState {
        return .{ .hold_timer = 0, .repeat_timer = 0 };
    }
};

/// Handles keyboard input for game selection navigation with continuous scrolling
/// Returns the new selected index based on arrow key presses
pub fn handleSelectionInput(current_index: usize, total_items: usize, state: *InputState, dt: f32) usize {
    var new_index = current_index;

    // Check for initial key press (immediate response)
    if (rl.isKeyPressed(.right)) {
        new_index = (current_index + 1) % total_items;
        state.hold_timer = 0;
        state.repeat_timer = 0;
    } else if (rl.isKeyPressed(.left)) {
        new_index = if (current_index == 0)
            total_items - 1
        else
            current_index - 1;
        state.hold_timer = 0;
        state.repeat_timer = 0;
    }
    // Handle continuous scrolling when held
    else if (rl.isKeyDown(.right)) {
        state.hold_timer += dt;

        // After initial delay, start repeating
        if (state.hold_timer >= state.initial_delay) {
            state.repeat_timer += dt;

            if (state.repeat_timer >= state.repeat_rate) {
                new_index = (current_index + 1) % total_items;
                state.repeat_timer = 0; // Reset repeat timer for next repeat
            }
        }
    } else if (rl.isKeyDown(.left)) {
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
        // No keys held - reset timers
        state.hold_timer = 0;
        state.repeat_timer = 0;
    }

    return new_index;
}

/// Checks if the user has confirmed their selection
pub fn isSelectionConfirmed() bool {
    return rl.isKeyPressed(.enter);
}
