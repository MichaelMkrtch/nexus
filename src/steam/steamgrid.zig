const std = @import("std");

pub const ArtPaths = struct {
    icon_path: ?[:0]const u8,
    hero_path: ?[:0]const u8,
};

fn getApiKey(allocator: std.mem.Allocator) ![]u8 {
    // Returns an owned slice you must free.
    return std.process.getEnvVarOwned(allocator, "STEAMGRIDDB_API_KEY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => error.ApiKeyMissing,
        else => err,
    };
}

fn getCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    const base = try std.fs.getAppDataDir(allocator, "Nexus");
    errdefer allocator.free(base);

    // Ensure the base Nexus directory exists
    std.fs.makeDirAbsolute(base) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const path = try std.fs.path.join(allocator, &.{ base, "art" });
    errdefer allocator.free(path);

    // Ensure art subdirectory exists
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    allocator.free(base);
    return path;
}

fn fileExists(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch return false;
    file.close();
    return true;
}

/// Find a cached file with any of the supported image extensions.
/// Returns an owned slice with the full path if found, null otherwise.
fn findCachedImage(allocator: std.mem.Allocator, base_path: []const u8) ?[]u8 {
    const extensions = [_][]const u8{ ".png", ".jpg", ".jpeg" };

    for (extensions) |ext| {
        const path = std.fmt.allocPrint(allocator, "{s}{s}", .{ base_path, ext }) catch continue;

        if (fileExists(path)) {
            return path; // Return owned path
        }
        allocator.free(path);
    }

    return null;
}

/// Extract file extension from URL (e.g., "https://example.com/image.jpg" -> ".jpg")
fn getExtensionFromUrl(url: []const u8) []const u8 {
    // Find the last '.' in the URL
    var i = url.len;
    while (i > 0) {
        i -= 1;
        if (url[i] == '.') {
            // Check if this looks like an image extension
            const ext = url[i..];
            if (std.mem.startsWith(u8, ext, ".png") or
                std.mem.startsWith(u8, ext, ".jpg") or
                std.mem.startsWith(u8, ext, ".jpeg"))
            {
                // Find where the extension ends (at ?, #, or end of string)
                var end: usize = i;
                while (end < url.len and url[end] != '?' and url[end] != '#') {
                    end += 1;
                }
                return url[i..end];
            }
        }
        // Stop at path separator to avoid going into domain
        if (url[i] == '/' or url[i] == '?') break;
    }
    return ".png"; // Default to .png if no extension found
}

/// Ensure directory for a given absolute file path exists.
fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dirname| {
        std.fs.makeDirAbsolute(dirname) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // ok, dir is already there
            else => return err,
        };
    }
}

/// Download URL directly into file on disk
fn downloadToFile(
    allocator: std.mem.Allocator,
    url: []const u8,
    abs_path: []const u8,
    api_key: []const u8,
) !void {
    _ = api_key; // CDN downloads don't need authentication

    try ensureParentDir(abs_path);

    var file = try std.fs.createFileAbsolute(abs_path, .{
        .truncate = true,
    });
    defer file.close();

    // std.Io.Writer style (0.15.1)
    var buf: [8 * 1024]u8 = undefined;
    var writer_wrapper = file.writer(&buf);
    const writer: *std.Io.Writer = &writer_wrapper.interface;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // CDN endpoints don't require authentication, just download directly
    const res = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = writer,
    });

    if (res.status != .ok) {
        std.log.warn("downloadToFile failed: HTTP {d} for URL: {s}", .{ @intFromEnum(res.status), url });
        return error.BadStatus;
    }

    try writer.flush();
}

/// Given a Steam appid, resolve the SteamGridDB game id.
fn fetchGameIdForSteamApp(allocator: std.mem.Allocator, api_key: []const u8, app_id: u32) !u32 {
    const url = try std.fmt.allocPrint(
        allocator,
        "https://www.steamgriddb.com/api/v2/games/steam/{d}",
        .{app_id},
    );
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body_writer = std.io.Writer.Allocating.init(allocator);
    defer body_writer.deinit();

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    const headers = [_]std.http.Header{
        .{ .name = "Authorization", .value = auth_value },
        .{ .name = "Accept", .value = "application/json" },
    };

    const res = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = &headers,
        .response_writer = &body_writer.writer,
    });

    if (res.status != .ok) {
        std.debug.print(
            "SteamGridDB games HTTP status for app {d}: {any}\n",
            .{ app_id, res.status },
        );
        return error.BadStatus;
    }

    const raw = try body_writer.toOwnedSlice();
    defer allocator.free(raw);

    const GameResp = struct {
        success: bool,
        data: ?struct {
            id: u32,
        } = null,
    };

    const parsed = std.json.parseFromSlice(GameResp, allocator, raw, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print(
            "SteamGridDB games JSON parse error for app {d}: {s}\nResponse:\n{s}\n",
            .{ app_id, @errorName(err), raw },
        );
        return err;
    };
    defer parsed.deinit();

    const value = parsed.value;

    if (!value.success or value.data == null) {
        std.debug.print(
            "SteamGridDB games no data for app {d}. Response:\n{s}\n",
            .{ app_id, raw },
        );
        return error.MissingData;
    }

    return value.data.?.id;
}

/// Pick best “icon” URL for a game id.
fn pickBestIconUrl(allocator: std.mem.Allocator, api_key: []const u8, game_id: u32) ![]u8 {
    const url = try std.fmt.allocPrint(
        allocator,
        "https://www.steamgriddb.com/api/v2/grids/game/{d}?types=static&sort=score&dimensions=1024x1024",
        .{game_id},
    );
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    const headers = [_]std.http.Header{
        .{ .name = "Authorization", .value = auth_value },
        .{ .name = "Accept", .value = "application/json" },
    };

    const fetch_res = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = &headers,
        .response_writer = &body.writer,
    });

    if (fetch_res.status != .ok) {
        return error.BadStatus;
    }

    const raw = try body.toOwnedSlice();
    defer allocator.free(raw);

    const IconResp = struct {
        success: bool,
        data: []struct {
            url: []u8,
        },
    };

    const parsed = try std.json.parseFromSlice(IconResp, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (!parsed.value.success or parsed.value.data.len == 0) {
        return error.MissingData;
    }

    const src = parsed.value.data[0].url;
    const copy = try allocator.dupe(u8, src);
    return copy;
}

/// Pick best “hero” URL for a game id.
fn pickBestHeroUrl(allocator: std.mem.Allocator, api_key: []const u8, game_id: u32) ![]u8 {
    const url = try std.fmt.allocPrint(
        allocator,
        "https://www.steamgriddb.com/api/v2/heroes/game/{d}?types=static&sort=score&dimensions=3840x1240",
        .{game_id},
    );
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    const headers = [_]std.http.Header{
        .{ .name = "Authorization", .value = auth_value },
        .{ .name = "Accept", .value = "application/json" },
    };

    const fetch_res = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = &headers,
        .response_writer = &body.writer,
    });

    if (fetch_res.status != .ok) {
        return error.BadStatus;
    }

    const raw = try body.toOwnedSlice();
    defer allocator.free(raw);

    const HeroResp = struct {
        success: bool,
        data: []struct {
            url: []u8,
        },
    };

    const parsed = try std.json.parseFromSlice(HeroResp, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (!parsed.value.success or parsed.value.data.len == 0) {
        return error.MissingData;
    }

    const src = parsed.value.data[0].url;
    const copy = try allocator.dupe(u8, src);
    return copy;
}

pub fn fetchAndCacheArt(allocator: std.mem.Allocator, app_id: u32) !ArtPaths {
    var gpa = allocator;

    const cache_root = try getCacheRoot(gpa);
    defer gpa.free(cache_root);

    // Build base paths without extensions: <cache_root>\icons\<app_id> and heroes\<app_id>
    var buf: [32]u8 = undefined;
    const app_id_str = std.fmt.bufPrint(&buf, "{d}", .{app_id}) catch unreachable;

    const icon_base = try std.fmt.allocPrint(gpa, "icons\\{s}", .{app_id_str});
    const hero_base = try std.fmt.allocPrint(gpa, "heroes\\{s}", .{app_id_str});
    defer {
        gpa.free(icon_base);
        gpa.free(hero_base);
    }

    const icon_base_full = try std.fs.path.join(gpa, &.{ cache_root, icon_base });
    const hero_base_full = try std.fs.path.join(gpa, &.{ cache_root, hero_base });
    defer {
        gpa.free(icon_base_full);
        gpa.free(hero_base_full);
    }

    // --- 1. Check cache first (look for any supported extension) -------------
    var icon_sentinel: ?[:0]const u8 = null;
    var hero_sentinel: ?[:0]const u8 = null;

    if (findCachedImage(gpa, icon_base_full)) |icon_path| {
        defer gpa.free(icon_path);
        const buf_icon = try gpa.allocSentinel(u8, icon_path.len, 0);
        std.mem.copyForwards(u8, buf_icon[0..icon_path.len], icon_path);
        icon_sentinel = buf_icon[0..icon_path.len :0];
    }

    if (findCachedImage(gpa, hero_base_full)) |hero_path| {
        defer gpa.free(hero_path);
        const buf_hero = try gpa.allocSentinel(u8, hero_path.len, 0);
        std.mem.copyForwards(u8, buf_hero[0..hero_path.len], hero_path);
        hero_sentinel = buf_hero[0..hero_path.len :0];
    }

    // If we already have at least an icon or hero, just return what we've got.
    if (icon_sentinel != null or hero_sentinel != null) {
        return ArtPaths{
            .icon_path = icon_sentinel,
            .hero_path = hero_sentinel,
        };
    }

    // --- 2. Hit SteamGridDB ---------------------------------------------------
    const api_key = try getApiKey(gpa);
    defer gpa.free(api_key);

    const game_id = fetchGameIdForSteamApp(gpa, api_key, app_id) catch |err| {
        std.log.warn("SteamGridDB: failed to resolve game id for app {d}: {s}", .{ app_id, @errorName(err) });
        return ArtPaths{
            .icon_path = null,
            .hero_path = null,
        };
    };

    var tmp_icon_url: ?[]u8 = null;
    var tmp_hero_url: ?[]u8 = null;
    errdefer if (tmp_icon_url) |u| gpa.free(u);
    errdefer if (tmp_hero_url) |u| gpa.free(u);

    // Ignore errors on one side so we can still get the other.
    tmp_icon_url = pickBestIconUrl(gpa, api_key, game_id) catch null;
    tmp_hero_url = pickBestHeroUrl(gpa, api_key, game_id) catch null;

    // Download and save with correct extension from URL
    if (tmp_icon_url) |icon_url| {
        const ext = getExtensionFromUrl(icon_url);
        const icon_full = try std.fmt.allocPrint(gpa, "{s}{s}", .{ icon_base_full, ext });
        defer gpa.free(icon_full);

        downloadToFile(gpa, icon_url, icon_full, api_key) catch |err| {
            std.log.warn("Failed to download icon for app {d}: {s}", .{ app_id, @errorName(err) });
        };
    }

    if (tmp_hero_url) |hero_url| {
        const ext = getExtensionFromUrl(hero_url);
        const hero_full = try std.fmt.allocPrint(gpa, "{s}{s}", .{ hero_base_full, ext });
        defer gpa.free(hero_full);

        downloadToFile(gpa, hero_url, hero_full, api_key) catch |err| {
            std.log.warn("Failed to download hero for app {d}: {s}", .{ app_id, @errorName(err) });
        };
    }

    if (tmp_icon_url) |u| gpa.free(u);
    if (tmp_hero_url) |u| gpa.free(u);

    // --- 3. Re-check cache after download ------------------------------------
    if (icon_sentinel == null) {
        if (findCachedImage(gpa, icon_base_full)) |icon_path| {
            defer gpa.free(icon_path);
            const buf_icon = try gpa.allocSentinel(u8, icon_path.len, 0);
            std.mem.copyForwards(u8, buf_icon[0..icon_path.len], icon_path);
            icon_sentinel = buf_icon[0..icon_path.len :0];
        }
    }

    if (hero_sentinel == null) {
        if (findCachedImage(gpa, hero_base_full)) |hero_path| {
            defer gpa.free(hero_path);
            const buf_hero = try gpa.allocSentinel(u8, hero_path.len, 0);
            std.mem.copyForwards(u8, buf_hero[0..hero_path.len], hero_path);
            hero_sentinel = buf_hero[0..hero_path.len :0];
        }
    }

    return ArtPaths{
        .icon_path = icon_sentinel,
        .hero_path = hero_sentinel,
    };
}
