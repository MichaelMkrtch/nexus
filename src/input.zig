const rl = @import("raylib");

/// Handles keyboard input for game selection navigation
/// Returns the new selected index based on arrow key presses
pub fn handleSelectionInput(current_index: usize, total_items: usize) usize {
    var new_index = current_index;

    if (rl.isKeyPressed(.right)) {
        new_index = (current_index + 1) % total_items;
    }

    if (rl.isKeyPressed(.left)) {
        new_index = if (current_index == 0)
            total_items - 1
        else
            current_index - 1;
    }

    return new_index;
}

/// Checks if the user has confirmed their selection
pub fn isSelectionConfirmed() bool {
    return rl.isKeyPressed(.enter);
}
