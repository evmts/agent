//! Localhost-only HTTP server backed by Zap (facil.io).
//! - Binds 127.0.0.1 only by default
//! - Exposes GET /api/health → {"status":"ok"}
//! - CORS restricted to exact localhost origins (http/https, IPv4/IPv6)
const std = @import("std");
const Allocator = std.mem.Allocator;
const zap = @import("zap");
const log = std.log.scoped(.http_server);

pub const Config = struct {
    /// Listening port. Use 0 to let OS pick (tests use fixed high port).
    port: u16 = 0,
    /// Network interface to bind (null-terminated C string for Zap).
    interface: [*:0]const u8 = "127.0.0.1",
    /// Enable request logging (Zap-level). Defaults false to reduce noise in tests.
    log: bool = false,
};

pub const Server = struct {
    const Self = @This();
    alloc: Allocator,
    cfg: Config,
    listener: zap.HttpListener,
    thread: ?std.Thread = null,
    started: bool = false,

    pub const CreateError = Allocator.Error;
    pub const StartError = error{AlreadyStarted} || std.Thread.SpawnError || zap.HttpError || zap.ListenError;

    pub fn create(alloc: Allocator, cfg: Config) CreateError!*Self {
        var self = try alloc.create(Self);
        errdefer alloc.destroy(self);
        try self.init(alloc, cfg);
        return self;
    }

    pub fn init(self: *Self, alloc: Allocator, cfg: Config) CreateError!void {
        self.* = .{
            .alloc = alloc,
            .cfg = cfg,
            .listener = zap.HttpListener.init(.{
                .port = cfg.port,
                .interface = cfg.interface,
                .on_request = onRequest,
                .log = cfg.log,
            }),
            .thread = null,
            .started = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.* = undefined; // poison
    }

    pub fn destroy(self: *Self) void {
        const alloc = self.alloc;
        if (self.started) self.stop();
        self.deinit();
        alloc.destroy(self);
    }

    /// Starts the Zap event loop on a background thread. Non-blocking.
    pub fn start(self: *Self) StartError!void {
        if (self.started) return error.AlreadyStarted;

        self.thread = try std.Thread.spawn(.{}, run, .{self});
        self.started = true;
    }
    /// Signals Zap loop to stop and joins the background thread.
    pub fn stop(self: *Self) void {
        zap.stop();
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
        self.started = false;
    }

    fn run(self: *Self) void {
        // Blocks until zap.stop() is called.
        if (self.listener.listen()) |_| {
            log.info("listening on 127.0.0.1:{}", .{self.cfg.port});
            zap.start(.{ .threads = 2, .workers = 1 });
        } else |err| {
            log.warn("listener.listen() failed: {}", .{err});
            self.started = false;
        }
    }
};

// Request handling

fn onRequest(r: zap.Request) anyerror!void {
    // CORS preflight
    const method = r.methodAsEnum();
    if (method == .OPTIONS) {
        setCorsHeaders(r);
        r.setStatus(.no_content);
        return;
    }

    const path = r.path orelse "/";
    log.debug("{s} {s}", .{ @tagName(method), path });
    if (std.mem.eql(u8, path, "/api/health") and method == .GET) {
        setCorsHeaders(r);
        try r.setContentType(.JSON);
        try r.sendBody("{\"status\":\"ok\"}");
        return;
    }

    setCorsHeaders(r);
    r.setStatus(.not_found);
    try r.sendBody("Not Found");
}

fn stripIpv6Brackets(host: []const u8) []const u8 {
    if (host.len >= 2 and host[0] == '[' and host[host.len - 1] == ']') return host[1 .. host.len - 1];
    return host;
}

fn parseOriginHost(origin: []const u8) ?struct { host: []const u8 } {
    const http = "http://";
    const https = "https://";
    var i: usize = 0;
    if (std.mem.startsWith(u8, origin, http)) {
        i = http.len;
    } else if (std.mem.startsWith(u8, origin, https)) {
        i = https.len;
    } else {
        return null; // unsupported scheme
    }
    if (i >= origin.len) return null;
    if (origin[i] == '[') {
        const close = std.mem.indexOfScalarPos(u8, origin, i, ']') orelse return null;
        return .{ .host = origin[i + 1 .. close] };
    }
    // IPv4 or hostname — read until ':' or '/' or end
    var end = origin.len;
    if (std.mem.indexOfScalarPos(u8, origin, i, ':')) |p| end = @min(end, p);
    if (std.mem.indexOfScalarPos(u8, origin, i, '/')) |p| end = @min(end, p);
    if (end <= i) return null;
    return .{ .host = origin[i..end] };
}

fn setCorsHeaders(r: zap.Request) void {
    // Reflect only strict localhost origins (http/https, IPv4/IPv6). When no Origin,
    // omit ACAO entirely.
    const origin_hdr = r.getHeaderCommon(.origin);
    if (origin_hdr) |o| {
        const parsed = parseOriginHost(o) orelse return;
        const host = stripIpv6Brackets(parsed.host);
        const is_local_host = std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "::1");
        if (is_local_host) {
            // Reflect exact origin and vary to avoid proxy cache confusion
            if (r.setHeader("Access-Control-Allow-Origin", o)) |_| {} else |e| log.warn("set ACAO failed: {}", .{e});
            if (r.setHeader("Vary", "Origin")) |_| {} else |e| log.warn("set Vary failed: {}", .{e});
        }
    }
    if (r.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")) |_| {} else |e| log.warn("set ACAM failed: {}", .{e});
    if (r.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")) |_| {} else |e| log.warn("set ACAH failed: {}", .{e});
}

// Tests

test "HttpServer create/destroy lifecycle" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var srv = try Server.create(alloc, .{});
    defer srv.destroy();
    try testing.expect(!srv.started);
}

const test_port_base: u16 = 18920;

test "HttpServer start/stop without requests" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var srv = try Server.create(alloc, .{ .port = test_port_base + 1 });
    defer srv.destroy();
    try srv.start();
    // Give zap time to spin up
    std.Thread.sleep(200 * std.time.ns_per_ms);
    srv.stop();
    try testing.expect(!srv.started);
}

fn httpGet(alloc: Allocator, url: []const u8) !struct { status: std.http.Status, body: []u8 } {
    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();

    var req = try client.request(.GET, try std.Uri.parse(url), .{});
    defer req.deinit();
    try req.sendBodiless();
    var redirect_buf: [1024]u8 = undefined;
    var resp = try req.receiveHead(&redirect_buf);

    const r = resp.reader(&[_]u8{});
    const body = try r.allocRemaining(alloc, std.io.Limit.limited(16 * 1024));
    return .{ .status = resp.head.status, .body = body };
}

test "health endpoint returns 200 JSON" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var srv = try Server.create(alloc, .{ .port = test_port_base + 2 });
    defer srv.destroy();
    try srv.start();
    defer srv.stop();
    std.Thread.sleep(150 * std.time.ns_per_ms);

    const res = try httpGet(alloc, "http://127.0.0.1:18922/api/health");
    defer alloc.free(res.body);
    try testing.expectEqual(std.http.Status.ok, res.status);
    try testing.expect(std.mem.indexOf(u8, res.body, "\"status\":\"ok\"") != null);
}

test "unknown route returns 404" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var srv = try Server.create(alloc, .{ .port = test_port_base + 3 });
    defer srv.destroy();
    try srv.start();
    defer srv.stop();
    std.Thread.sleep(150 * std.time.ns_per_ms);

    const res = try httpGet(alloc, "http://127.0.0.1:18923/api/does-not-exist");
    defer alloc.free(res.body);
    try testing.expectEqual(std.http.Status.not_found, res.status);
}

// raw TCP helper removed; std.http.Client used in tests below

test "CORS reflect for localhost origins and reject others" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var srv = try Server.create(alloc, .{ .port = test_port_base + 4 });
    defer srv.destroy();
    try srv.start();
    defer srv.stop();
    std.Thread.sleep(150 * std.time.ns_per_ms);

    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();
    const url = try std.Uri.parse("http://127.0.0.1:18924/api/health");

    // Allowed: https://localhost:3000
    var req1 = try client.request(.GET, url, .{ .extra_headers = &.{.{ .name = "origin", .value = "https://localhost:3000" }} });
    defer req1.deinit();
    try req1.sendBodiless();
    var buf1: [1024]u8 = undefined;
    var res1 = try req1.receiveHead(&buf1);
    var it1 = res1.head.iterateHeaders();
    var found1 = false;
    while (it1.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "Access-Control-Allow-Origin") and std.mem.eql(u8, h.value, "https://localhost:3000")) {
            found1 = true;
            break;
        }
    }
    try testing.expect(found1);

    // Allowed: http://[::1]:5173
    var req2 = try client.request(.GET, url, .{ .extra_headers = &.{.{ .name = "origin", .value = "http://[::1]:5173" }} });
    defer req2.deinit();
    try req2.sendBodiless();
    var buf2: [1024]u8 = undefined;
    var res2 = try req2.receiveHead(&buf2);
    var it2 = res2.head.iterateHeaders();
    var found2 = false;
    while (it2.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "Access-Control-Allow-Origin") and std.mem.eql(u8, h.value, "http://[::1]:5173")) {
            found2 = true;
            break;
        }
    }
    try testing.expect(found2);

    // Rejected: https://evil.com (no ACAO header)
    var req3 = try client.request(.GET, url, .{ .extra_headers = &.{.{ .name = "origin", .value = "https://evil.com" }} });
    defer req3.deinit();
    try req3.sendBodiless();
    var buf3: [1024]u8 = undefined;
    var res3 = try req3.receiveHead(&buf3);
    var it3 = res3.head.iterateHeaders();
    var present = false;
    while (it3.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "Access-Control-Allow-Origin")) {
            present = true;
            break;
        }
    }
    try testing.expect(!present);
}

test "OPTIONS preflight returns 204 with CORS headers" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var srv = try Server.create(alloc, .{ .port = test_port_base + 5 });
    defer srv.destroy();
    try srv.start();
    defer srv.stop();
    std.Thread.sleep(150 * std.time.ns_per_ms);
    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();
    const url = try std.Uri.parse("http://127.0.0.1:18925/api/health");
    var req = try client.request(.OPTIONS, url, .{ .extra_headers = &.{ .{ .name = "origin", .value = "http://localhost:3000" }, .{ .name = "access-control-request-method", .value = "GET" } } });
    defer req.deinit();
    try req.sendBodiless();
    var buf: [1024]u8 = undefined;
    var res = try req.receiveHead(&buf);
    try testing.expectEqual(std.http.Status.no_content, res.head.status);
    var it = res.head.iterateHeaders();
    var have_methods = false;
    var have_origin = false;
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "Access-Control-Allow-Methods")) have_methods = true;
        if (std.ascii.eqlIgnoreCase(h.name, "Access-Control-Allow-Origin") and std.mem.eql(u8, h.value, "http://localhost:3000")) have_origin = true;
    }
    try testing.expect(have_methods and have_origin);
}

test "start() twice returns error.AlreadyStarted" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var srv = try Server.create(alloc, .{ .port = test_port_base + 6 });
    defer srv.destroy();
    try srv.start();
    std.Thread.sleep(100 * std.time.ns_per_ms);
    const err = srv.start() catch |e| e;
    try testing.expect(err == error.AlreadyStarted);
    srv.stop();
}
