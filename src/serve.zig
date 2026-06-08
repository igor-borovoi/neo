//! Minimal static file server for the wasm dev workflow.
//!
//! Serves files from a directory over HTTP/1.1 on 127.0.0.1. Supports GET and
//! HEAD; HEAD is what `web/neo.js`'s auto-reload poll uses, comparing the
//! `last-modified` + `content-length` headers to detect rebuilds. Each response
//! sets `connection: close` so a single accept loop never blocks on an idle
//! keep-alive connection (the poll opens several parallel HEAD requests).
//!
//! Usage: neo-serve [dir] [port]   (defaults: zig-out/web, 8000)

const std = @import("std");
const http = std.http;
const Io = std.Io;
const net = std.Io.net;

const max_file_bytes = 64 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // Parse optional [dir] [port] positional arguments.
    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next(); // program name
    const dir_path = if (args.next()) |a| a else "zig-out/web";
    const port: u16 = if (args.next()) |a|
        std.fmt.parseInt(u16, a, 10) catch {
            std.debug.print("Error: invalid port: {s}\n", .{a});
            std.process.exit(1);
        }
    else
        8000;

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{}) catch |err| {
        std.debug.print("Error: cannot open directory '{s}': {s}\n", .{ dir_path, @errorName(err) });
        std.process.exit(1);
    };
    defer dir.close(io);

    var addr: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = addr.listen(io, .{ .reuse_address = true }) catch |err| {
        std.debug.print("Error: cannot listen on 127.0.0.1:{d}: {s}\n", .{ port, @errorName(err) });
        std.process.exit(1);
    };
    defer server.deinit(io);

    std.debug.print("Serving '{s}' at http://localhost:{d} (Ctrl+C to stop)\n", .{ dir_path, port });

    var recv_buf: [16 * 1024]u8 = undefined;
    var send_buf: [16 * 1024]u8 = undefined;

    while (true) {
        const stream = server.accept(io) catch continue;
        handleConnection(io, gpa, dir, stream, &recv_buf, &send_buf) catch {};
        stream.close(io);
    }
}

fn handleConnection(
    io: Io,
    gpa: std.mem.Allocator,
    dir: std.Io.Dir,
    stream: net.Stream,
    recv_buf: []u8,
    send_buf: []u8,
) !void {
    var reader = stream.reader(io, recv_buf);
    var writer = stream.writer(io, send_buf);
    var server = http.Server.init(&reader.interface, &writer.interface);

    var request = server.receiveHead() catch return;
    try serveFile(io, gpa, dir, &request);
}

fn serveFile(io: Io, gpa: std.mem.Allocator, dir: std.Io.Dir, request: *http.Server.Request) !void {
    const path = resolvePath(request.head.target);
    if (path == null) {
        try request.respond("400 Bad Request\n", .{ .status = .bad_request, .keep_alive = false });
        return;
    }
    const rel = path.?;

    // Stat first so a HEAD response carries the same metadata as GET without
    // reading the body. last-modified uses the mtime as raw nanoseconds — the
    // dev-reload poll only compares the string for equality, never parses it.
    const stat = dir.statFile(io, rel, .{}) catch {
        try request.respond("404 Not Found\n", .{ .status = .not_found, .keep_alive = false });
        return;
    };

    var lm_buf: [32]u8 = undefined;
    const last_modified = std.fmt.bufPrint(&lm_buf, "{d}", .{stat.mtime.toNanoseconds()}) catch "0";

    const headers = [_]http.Header{
        .{ .name = "content-type", .value = contentType(rel) },
        .{ .name = "last-modified", .value = last_modified },
        .{ .name = "cache-control", .value = "no-store" },
    };

    const body = dir.readFileAlloc(io, rel, gpa, .limited(max_file_bytes)) catch {
        try request.respond("500 Internal Server Error\n", .{ .status = .internal_server_error, .keep_alive = false });
        return;
    };
    defer gpa.free(body);

    // respond() omits the body for HEAD requests but still reports body.len as
    // content-length, so GET and HEAD agree without a separate code path.
    try request.respond(body, .{ .keep_alive = false, .extra_headers = &headers });
}

/// Map a request target to a safe relative file path, or null if it escapes
/// the served directory. Strips the query string and a leading slash, maps "/"
/// to index.html, and rejects any "..".
fn resolvePath(target: []const u8) ?[]const u8 {
    var p = target;
    if (std.mem.indexOfScalar(u8, p, '?')) |q| p = p[0..q];
    if (p.len == 0 or p[0] != '/') return null;
    p = p[1..];
    if (p.len == 0) return "index.html";
    if (std.mem.indexOf(u8, p, "..") != null) return null;
    return p;
}

fn contentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    const map = .{
        .{ ".html", "text/html; charset=utf-8" },
        .{ ".js", "text/javascript; charset=utf-8" },
        .{ ".wasm", "application/wasm" },
        .{ ".css", "text/css; charset=utf-8" },
        .{ ".json", "application/json" },
        .{ ".svg", "image/svg+xml" },
        .{ ".png", "image/png" },
        .{ ".ico", "image/x-icon" },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, ext, entry[0])) return entry[1];
    }
    return "application/octet-stream";
}
