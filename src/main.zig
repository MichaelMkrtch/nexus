const std = @import("std");
const nexus = @import("nexus");
const rl = @import("raylib");

pub fn main() !void {
    const screen_w = 800;
    const screen_h = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true, .window_highdpi = true, .window_resizable = true });

    rl.initWindow(screen_w, screen_h, "Nexus");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // state
    var selected_index: i32 = 0;
    const game_count: i32 = 2;

    // Main loop
    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.down)) {
            selected_index += 1;
            if (selected_index >= game_count) selected_index = 0; // wrap
        }

        if (rl.isKeyPressed(.up)) {
            selected_index -= 1;
            if (selected_index < 0) selected_index = game_count - 1; // wrap
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        rl.drawRectangle(0, 0, screen_w, screen_h, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 255 });
        rl.drawText("Nexus", 40, 40, 40, .white);

        const base_y: i32 = 160;
        const gap_y: i32 = 60;

        // Game 1
        {
            const idx: i32 = 0;
            const y = base_y + gap_y * idx;
            const is_selected = selected_index == idx;

            if (is_selected) {
                rl.drawText(">", 60, y, 30, .white);
            }

            const color: rl.Color = if (is_selected) .yellow else .gray;
            rl.drawText("Game 1", 80, y, 30, color);
        }

        // Game 2
        {
            const idx: i32 = 1;
            const y = base_y + gap_y * idx;
            const is_selected = selected_index == idx;

            if (is_selected) {
                rl.drawText(">", 60, y, 30, .white);
            }

            const color: rl.Color = if (is_selected) .yellow else .gray;
            rl.drawText("Game 2", 80, y, 30, color);
        }
        //----------------------------------------------------------------------------------
    }
}
