const std = @import("std");
const steam_types = @import("steam_types.zig");
const vdf = @import("vdf.zig");

const Game = steam_types.Game;
const LibraryFolder = steam_types.LibraryFolder;

/// Public entrypoint for the rest of the app.
/// TODO: add a steam_remote.enrichGames() call on top
pub fn getInstalledGames(allocator: std.mem.Allocator) ![]Game {
    const gpa = allocator;

    // 1. Find Steam install root
    const steam_root = try detectSteamRoot(gpa);
    defer gpa.free(steam_root);

    // 2. Parse libraryFolders.vdf
    const libraries = try parseLibraryFolders(gpa, steam_root);
    defer {
        // free library folder paths
        for (libraries) |lib| {
            gpa.free(lib.path);
        }
        gpa.free(libraries);
    }

    // 3. For each library, parse appmanifest_*.acf
    return try loadGamesFromLibraries(gpa, libraries);
}

/// Build full install path for a game:
/// <library_root>\steamapps\common\<install_dir>
/// Note: this does not change the Game struct; it computes a path
/// on demand when you need it.
pub fn getInstallPath(allocator: std.mem.Allocator, game: Game) ![]u8 {
    return std.fs.path.join(allocator, &.{
        game.library_root, // ex: "D:\\Steam"
        "steamapps",
        "common",
        game.install_dir, // ex: "Cyberpunk 2077"
    });
}

// Find Steam root directory
fn detectSteamRoot(allocator: std.mem.Allocator) ![]u8 {
    const gpa = allocator;

    // Candidate Steam *install* roots (not libraries)
    const candidates = [_][]const u8{
        "C:\\Program Files (x86)\\Steam",
        "C:\\Program Files\\Steam",
    };

    for (candidates) |path| {
        // Build "<path>\\steam.exe"
        const exe_path = try std.fs.path.join(gpa, &.{ path, "steam.exe" });
        defer gpa.free(exe_path);

        // Try to open steam.exe to confirm this is a valid Steam root
        if (std.fs.openFileAbsolute(exe_path, .{ .mode = .read_only })) |file| {
            file.close();

            // Copy the root path into allocator-owned memory and return
            const buffer = try gpa.alloc(u8, path.len);
            std.mem.copyForwards(u8, buffer, path);
            return buffer;
        } else |_| {
            // Could not open steam.exe at this path, try the next candidate
            continue;
        }
    }

    return error.SteamRootNotFound;
}

fn parseLibraryFolders(allocator: std.mem.Allocator, steam_root: []const u8) ![]LibraryFolder {
    const gpa = allocator;

    // Build "<steam_root>\\steamapps\\libraryfolders.vdf"
    var path_buffer = std.ArrayList(u8){};
    defer path_buffer.deinit(gpa);

    // First try: <steam_root>\libraryfolder.vdf
    try path_buffer.appendSlice(gpa, steam_root);
    try path_buffer.appendSlice(gpa, "\\steamapps\\libraryfolders.vdf");
    const primary_path = path_buffer.items;

    var file = try std.fs.openFileAbsolute(primary_path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    const contents = try gpa.alloc(u8, @as(usize, @intCast(stat.size)));
    defer gpa.free(contents);

    const bytes_read = try file.readAll(contents);
    if (bytes_read != contents.len) return error.UnexpectedEof;

    // Parse VDF into a generic tree
    // root represents the outermost object, ex: { "libraryfolders": { ... } }
    const root = try vdf.parse(allocator, contents);
    defer vdf.freeTree(allocator, root);

    // Extract "libraryfolders" object
    const libraries_node = try vdf.getChild(root, "libraryfolders");

    // Collect entries
    // libraryfolders entries are usually "0", "1", "2"...
    var list = std.ArrayList(LibraryFolder){};

    var it = vdf.childIterator(libraries_node);
    while (it.next()) |child| {
        // Typical shape:
        // "0" { "path" "D:\\Steam" ... }
        const path_node = vdf.getChild(child, "path") catch continue;
        const path_value = try vdf.asString(path_node);

        // Copy path into owned memory
        const path_buffer2 = try gpa.alloc(u8, path_value.len);
        std.mem.copyForwards(u8, path_buffer2, path_value);

        try list.append(gpa, LibraryFolder{
            .path = path_buffer2,
        });
    }

    return try list.toOwnedSlice(gpa);
}

/// For each LibraryFolder, scan steamapps/appmanifest_*.acf
/// and build Game entries
fn loadGamesFromLibraries(
    allocator: std.mem.Allocator,
    libs: []const LibraryFolder,
) ![]Game {
    const gpa = allocator;
    var games = std.ArrayList(Game){};

    for (libs) |lib| {
        // Build "<lib.path>\\steamapps"
        var buffer = std.ArrayList(u8){};
        defer buffer.deinit(gpa);

        const steamapps_path = try std.fs.path.join(gpa, &.{ lib.path, "steamapps" });
        defer gpa.free(steamapps_path);

        var dir = std.fs.openDirAbsolute(steamapps_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.startsWith(u8, entry.name, "appmanifest_")) continue;
            if (!std.mem.endsWith(u8, entry.name, ".acf")) continue;

            var game = try parseAppManifestFile(
                gpa,
                steamapps_path,
                entry.name,
            );

            // Skip utility/meta apps
            if (isUtilityApp(game.app_id)) {
                // Free allocated memory before skipping
                steam_types.freeGame(gpa, game);
                continue;
            }

            game.full_path = try getInstallPath(gpa, game);

            try games.append(gpa, game);
        }
    }

    return try games.toOwnedSlice(gpa);
}

/// Parse a single appmanifest_XXX.acf into a Game
/// For the first implementation, we focus on fields we know exist
fn parseAppManifestFile(
    allocator: std.mem.Allocator,
    steamapps_path: []const u8,
    filename: []const u8,
) !Game {
    const gpa = allocator;

    // Build "<steamapps_path>\<filename>"
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(gpa);
    try buffer.appendSlice(gpa, steamapps_path);
    try buffer.append(gpa, '\\');
    try buffer.appendSlice(gpa, filename);
    const full_path = buffer.items;

    var file = try std.fs.openFileAbsolute(full_path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    const contents = try gpa.alloc(u8, @as(usize, @intCast(stat.size)));
    defer gpa.free(contents);
    _ = try file.readAll(contents);

    const root = try vdf.parse(gpa, contents);
    defer vdf.freeTree(gpa, root);
    const app_state = try vdf.getChild(root, "AppState");

    const app_id_str = try vdf.asString(try vdf.getChild(app_state, "appid"));
    const name_str = try vdf.asString(try vdf.getChild(app_state, "name"));
    const installdir = try vdf.asString(try vdf.getChild(app_state, "installdir"));
    const size_str = vdf.asString(try vdf.getChild(app_state, "SizeOnDisk")) catch "0";

    const app_id = try std.fmt.parseInt(u32, app_id_str, 10);
    const size_on_disk = std.fmt.parseInt(u64, size_str, 10) catch 0;

    // Derive <library_root> from "<library_root>\steamapps"
    const suffix = "\\steamapps";
    if (steamapps_path.len <= suffix.len or
        !std.mem.endsWith(u8, steamapps_path, suffix))
    {
        return error.InvalidSteamappsPath;
    }

    const library_root_slice = steamapps_path[0 .. steamapps_path.len - suffix.len];

    // library_root
    const library_root_buffer = try gpa.alloc(u8, library_root_slice.len);
    std.mem.copyForwards(u8, library_root_buffer, library_root_slice);

    // name
    const name_copy = try gpa.alloc(u8, name_str.len);
    std.mem.copyForwards(u8, name_copy, name_str);
    // install directory
    const install_copy = try gpa.alloc(u8, installdir.len);
    std.mem.copyForwards(u8, install_copy, installdir);

    // Placeholder exe_path for now; we'll resolve later via scanning.
    const exe_empty = try gpa.alloc(u8, 0);

    // Placeholder full_path - will be set by caller
    const full_path_empty = try gpa.alloc(u8, 0);

    return Game{
        .app_id = app_id,
        .name = name_copy,
        .library_root = library_root_buffer,
        .install_dir = install_copy,
        .full_path = full_path_empty,
        .exe_path = exe_empty,
        .size_on_disk = size_on_disk,
        .cover_image_path = null,
    };
}

/// Return true if app is not a game
fn isUtilityApp(app_id: u32) bool {
    return switch (app_id) {
        228980 => true, // Steamworks Common Redistributables
        431960 => true, // Wallpaper Engine
        else => false,
    };
}
