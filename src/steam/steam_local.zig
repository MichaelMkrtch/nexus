const std = @import("std");
const steam_types = @import("steam_types.zig");
const vdf = @import("vdf.zig");
const steamgrid = @import("steamgrid.zig");

const Game = steam_types.Game;
const LibraryFolder = steam_types.LibraryFolder;

pub const GameLists = struct {
    games: []Game,
    games_without_exe: []Game,
};

pub fn freeGameLists(allocator: std.mem.Allocator, lists: GameLists) void {
    const gpa = allocator;

    for (lists.games) |g| {
        steam_types.freeGame(gpa, g);
    }
    for (lists.games_without_exe) |g| {
        steam_types.freeGame(gpa, g);
    }

    gpa.free(lists.games);
    gpa.free(lists.games_without_exe);
}

fn asciiLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len and
            asciiLower(haystack[i + j]) == asciiLower(needle[j]))
        {
            j += 1;
        }
        if (j == needle.len) return true;
    }
    return false;
}

/// Public entrypoint for the rest of the app.
/// TODO: add a steam_remote.enrichGames() call on top
pub fn getInstalledGames(allocator: std.mem.Allocator) !GameLists {
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
    errdefer {
        for (list.items) |lib| {
            gpa.free(lib.path);
        }
        list.deinit(gpa);
    }

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
/// and build Game entries. Returns both games with and without a
/// successfully resolved executable.
fn loadGamesFromLibraries(
    allocator: std.mem.Allocator,
    libs: []const LibraryFolder,
) !GameLists {
    const gpa = allocator;

    var games = std.ArrayList(Game){};
    errdefer {
        for (games.items) |g| steam_types.freeGame(gpa, g);
        games.deinit(gpa);
    }

    var games_without_exe = std.ArrayList(Game){};
    errdefer {
        for (games_without_exe.items) |g| steam_types.freeGame(gpa, g);
        games_without_exe.deinit(gpa);
    }

    for (libs) |lib| {
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
                steam_types.freeGame(gpa, game);
                continue;
            }

            // Replace placeholder full_path with the real install path
            gpa.free(game.full_path);
            game.full_path = try getInstallPath(gpa, game);

            const art = steamgrid.fetchAndCacheArt(gpa, game.app_id) catch |err| blk: {
                std.debug.print(
                    "SteamGridDB error for app {d}: {s}\n",
                    .{ game.app_id, @errorName(err) },
                );
                break :blk steamgrid.ArtPaths{ .icon_path = null, .hero_path = null };
            };

            game.cover_image_path = art.icon_path;
            game.hero_image_path = art.hero_path;

            // Try to resolve the exe path, but do not fail the whole scan
            if (resolveExePath(gpa, &game)) {
                // Executable resolved successfully
                try games.append(gpa, game);
            } else |err| switch (err) {
                // Executable not found: keep the game, but track separately
                error.ExecutableNotResolved => {
                    try games_without_exe.append(gpa, game);
                },
                // Some other error (I/O, permissions, etc.) – bail out
                else => {
                    steam_types.freeGame(gpa, game);
                    return err;
                },
            }
        }
    }

    const games_slice = try games.toOwnedSlice(gpa);
    const games_without_exe_slice = try games_without_exe.toOwnedSlice(gpa);

    return GameLists{
        .games = games_slice,
        .games_without_exe = games_without_exe_slice,
    };
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

    // Placeholder full_path - will be set by caller
    const full_path_empty = try gpa.alloc(u8, 0);

    return Game{
        .app_id = app_id,
        .name = name_copy,
        .library_root = library_root_buffer,
        .install_dir = install_copy,
        .full_path = full_path_empty,
        .exe_path = null,
        .size_on_disk = size_on_disk,
        .cover_image_path = null,
        .hero_image_path = null,
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

pub fn resolveExePath(allocator: std.mem.Allocator, game: *Game) !void {
    const gpa = allocator;

    var best_path: ?[]u8 = null;
    var best_score: i32 = std.math.minInt(i32);
    errdefer if (best_path) |p| gpa.free(p);

    try findExeRecursive(gpa, game.full_path, 0, game.install_dir, &best_path, &best_score);

    if (best_path) |path| {
        if (game.exe_path) |old| {
            gpa.free(old);
        }
        game.exe_path = path;
        return;
    }

    // nothing suitable found
    return error.ExecutableNotResolved;
}

fn findExeRecursive(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    depth: u32,
    install_name: []const u8,
    best_path: *?[]u8,
    best_score: *i32,
) !void {
    const gpa = allocator;

    if (depth > 5) return; // prevent runaway recursion

    var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
            const full = try std.fs.path.join(gpa, &.{ dir_path, entry.name });

            var file = try std.fs.openFileAbsolute(full, .{ .mode = .read_only });
            const stat = try file.stat();
            file.close();

            const score = scoreExeCandidate(full, entry.name, stat.size, install_name);

            if (score > best_score.*) {
                // replace previous best
                if (best_path.*) |old| gpa.free(old);
                best_score.* = score;
                best_path.* = full;
            } else {
                // discard this candidate
                gpa.free(full);
            }
        }

        if (entry.kind == .directory) {
            const sub = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
            defer gpa.free(sub);

            try findExeRecursive(gpa, sub, depth + 1, install_name, best_path, best_score);
        }
    }
}

fn normalizeLowerAscii(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const gpa = allocator;

    var buffer = try gpa.alloc(u8, s.len);
    var j: usize = 0;

    for (s) |c| {
        var out = c;
        if (c >= 'A' and c <= 'Z') {
            out = c + 32; // lowercase
        }
        // keep alnum and spaces only for now
        if ((out >= 'a' and out <= 'z') or
            (out >= '0' and out <= '9') or
            out == ' ')
        {
            buffer[j] = out;
            j += 1;
        }
    }
    return buffer[0..j];
}

/// Scoring function to help pick the exe most likely to be the game
fn scoreExeCandidate(
    file_path: []const u8,
    file_name: []const u8,
    file_size: u64,
    install_name: []const u8,
) i32 {
    var score: i32 = 0;

    if (!std.mem.endsWith(u8, file_name, ".exe")) return score;

    // Strip extension
    const base_name = file_name[0 .. file_name.len - ".exe".len];

    // 1) Size scoring
    const MB: u64 = 1024 * 1024;
    const size_mb: u64 = file_size / MB;
    const clamped_mb: u64 = if (size_mb > 500) 500 else size_mb;
    // Scale down to safe i32 range
    // Max of +1000 from size
    score += @as(i32, @intCast(clamped_mb)) * 2;

    // 2) Name similarity to install folder
    if (containsIgnoreCase(base_name, install_name)) {
        score += 300;
    }

    // Common shipping patterns
    const good_words = [_][]const u8{ "win64", "shipping", "game", "client" };
    for (good_words) |w| {
        if (containsIgnoreCase(base_name, w)) {
            score += 80;
        }
    }

    // 3) Directory heuristics
    const bad_dirs = [_][]const u8{ "redist", "tools", "support" };
    const good_dirs = [_][]const u8{ "win64", "binaries", "bin", "x64" };

    for (good_dirs) |w| {
        if (containsIgnoreCase(file_path, w)) {
            score += 120;
        }
    }
    for (bad_dirs) |w| {
        if (containsIgnoreCase(file_path, w)) {
            score -= 200;
        }
    }

    // 4) Penalties for obviously wrong things
    const bad_words2 = [_][]const u8{ "crash", "unins", "setup", "install", "report", "error", "config" };
    for (bad_words2) |w| {
        if (containsIgnoreCase(base_name, w)) {
            score -= 400;
        }
    }

    return score;
}

pub fn launchGame(allocator: std.mem.Allocator, game: *Game) !void {
    const exe = game.exe_path orelse return error.ExecutableNotResolved;

    var args = [_][]const u8{exe};

    var child = std.process.Child.init(&args, allocator);

    child.cwd = game.full_path;

    try child.spawn();
}
