//! CSRF (Cross-Site Request Forgery) protection middleware
//!
//! Validates CSRF tokens on all state-changing requests (POST, PUT, PATCH, DELETE).
//! Tokens are generated per session and stored in memory with expiration.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.csrf);

const CSRF_HEADER_NAME = "X-CSRF-Token";
const CSRF_COOKIE_NAME = "csrf_token";
const TOKEN_LENGTH = 32; // 32 bytes = 256 bits
const TOKEN_EXPIRY_MS = 24 * 60 * 60 * 1000; // 24 hours

/// CSRF token with expiration
const CsrfToken = struct {
    token: [TOKEN_LENGTH * 2]u8, // hex-encoded (64 chars)
    session_key: []const u8,
    expires_at: i64, // milliseconds since epoch
};

/// Thread-safe CSRF token store
pub const CsrfStore = struct {
    allocator: std.mem.Allocator,
    tokens: std.StringHashMap(CsrfToken),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) CsrfStore {
        return CsrfStore{
            .allocator = allocator,
            .tokens = std.StringHashMap(CsrfToken).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *CsrfStore) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.tokens.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.session_key);
        }
        self.tokens.deinit();
    }

    /// Generate a new CSRF token for a session
    pub fn generateToken(self: *CsrfStore, session_key: []const u8) ![]const u8 {
        // Generate random bytes
        var random_bytes: [TOKEN_LENGTH]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        // Convert to hex
        var token: [TOKEN_LENGTH * 2]u8 = undefined;
        const hex = std.fmt.bytesToHex(random_bytes, .lower);
        @memcpy(&token, &hex);

        const now = std.time.milliTimestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Store token with session association
        const token_key = try self.allocator.dupe(u8, &token);
        errdefer self.allocator.free(token_key);

        const session_key_copy = try self.allocator.dupe(u8, session_key);
        errdefer self.allocator.free(session_key_copy);

        try self.tokens.put(token_key, CsrfToken{
            .token = token,
            .session_key = session_key_copy,
            .expires_at = now + TOKEN_EXPIRY_MS,
        });

        return token_key;
    }

    /// Validate a CSRF token for a session
    pub fn validateToken(self: *CsrfStore, token: []const u8, session_key: ?[]const u8) bool {
        // Can't validate without a session
        if (session_key == null) return false;

        self.mutex.lock();
        defer self.mutex.unlock();

        const csrf_token = self.tokens.get(token) orelse return false;

        const now = std.time.milliTimestamp();

        // Check expiration
        if (now > csrf_token.expires_at) {
            return false;
        }

        // Check session association
        if (!std.mem.eql(u8, csrf_token.session_key, session_key.?)) {
            return false;
        }

        return true;
    }

    /// Remove a token from the store
    pub fn removeToken(self: *CsrfStore, token: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tokens.fetchRemove(token)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.session_key);
        }
    }

    /// Clean up expired tokens
    pub fn cleanupExpired(self: *CsrfStore) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.tokens.iterator();
        while (iter.next()) |entry| {
            if (now > entry.value_ptr.expires_at) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |token| {
            if (self.tokens.fetchRemove(token)) |entry| {
                self.allocator.free(entry.key);
                self.allocator.free(entry.value.session_key);
            }
        }

        if (to_remove.items.len > 0) {
            log.debug("Cleaned up {d} expired CSRF tokens", .{to_remove.items.len});
        }
    }
};

/// CSRF middleware configuration
pub const CsrfConfig = struct {
    /// Whether CSRF protection is enabled
    enabled: bool = true,
    /// Whether to skip CSRF for Bearer token authentication
    skip_bearer_auth: bool = true,
};

pub const default_config = CsrfConfig{};

/// Check if request method requires CSRF protection
fn requiresCsrfProtection(method: httpz.Method) bool {
    return method == .POST or method == .PUT or method == .PATCH or method == .DELETE;
}

/// Extract CSRF token from request header
fn getTokenFromHeader(req: *httpz.Request) ?[]const u8 {
    return req.headers.get(CSRF_HEADER_NAME);
}

/// CSRF protection middleware
/// Returns a middleware function configured with the given store and config
pub fn csrfMiddleware(store: *CsrfStore, config: CsrfConfig) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            // Skip if CSRF is disabled
            if (!config.enabled) {
                return true;
            }

            // Safe methods don't need CSRF protection
            if (!requiresCsrfProtection(req.method)) {
                return true;
            }

            // Skip CSRF for Bearer token authentication if configured
            if (config.skip_bearer_auth) {
                const auth_header = req.headers.get("authorization");
                if (auth_header != null and std.mem.startsWith(u8, auth_header.?, "Bearer ")) {
                    log.debug("Skipping CSRF check for Bearer token auth", .{});
                    return true;
                }
            }

            // Get CSRF token from request header
            const token = getTokenFromHeader(req) orelse {
                log.warn("CSRF token missing from {s} {s}", .{ @tagName(req.method), req.url.path });
                res.status = 403;
                res.content_type = .JSON;
                try res.writer().writeAll("{\"error\":\"CSRF token missing\"}");
                return false;
            };

            // Validate token against session
            if (!store.validateToken(token, ctx.session_key)) {
                log.warn("Invalid CSRF token for {s} {s}", .{ @tagName(req.method), req.url.path });
                res.status = 403;
                res.content_type = .JSON;
                try res.writer().writeAll("{\"error\":\"Invalid CSRF token\"}");
                return false;
            }

            log.debug("CSRF token validated for {s} {s}", .{ @tagName(req.method), req.url.path });
            return true;
        }
    }.handler;
}

/// Middleware to generate and set CSRF token cookie
/// Should be called after auth middleware to ensure session_key is set
pub fn csrfTokenMiddleware(store: *CsrfStore) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            _ = req;

            // Only generate token if user has a session
            if (ctx.session_key) |session_key| {
                // Generate token for session
                const token = try store.generateToken(session_key);

                // Set cookie with token
                var cookie_buf: [256]u8 = undefined;
                const secure = if (ctx.config.is_production) "; Secure" else "";

                // Note: CSRF cookie is NOT HttpOnly because client JS needs to read it
                // and send it back in X-CSRF-Token header. This is safe because the token
                // is validated server-side and tied to the session.
                const cookie = try std.fmt.bufPrint(&cookie_buf, "{s}={s}; Path=/; SameSite=Strict; Max-Age={d}{s}", .{
                    CSRF_COOKIE_NAME,
                    token,
                    TOKEN_EXPIRY_MS / 1000, // Convert to seconds
                    secure,
                });

                res.headers.add("Set-Cookie", cookie);
                log.debug("Generated CSRF token for session", .{});
            }

            return true;
        }
    }.handler;
}

// ============================================================================
// Tests
// ============================================================================

test "CsrfStore init and deinit" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    try std.testing.expect(store.tokens.count() == 0);
}

test "generateToken creates unique tokens" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token1 = try store.generateToken("session1");
    const token2 = try store.generateToken("session1");

    try std.testing.expect(!std.mem.eql(u8, token1, token2));
    try std.testing.expectEqual(@as(usize, 2), store.tokens.count());
}

test "validateToken accepts valid token" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token = try store.generateToken("session1");
    try std.testing.expect(store.validateToken(token, "session1"));
}

test "validateToken rejects wrong session" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token = try store.generateToken("session1");
    try std.testing.expect(!store.validateToken(token, "session2"));
}

test "validateToken rejects missing session" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token = try store.generateToken("session1");
    try std.testing.expect(!store.validateToken(token, null));
}

test "validateToken rejects invalid token" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    _ = try store.generateToken("session1");
    try std.testing.expect(!store.validateToken("invalid_token", "session1"));
}

test "removeToken removes token from store" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token = try store.generateToken("session1");
    try std.testing.expectEqual(@as(usize, 1), store.tokens.count());

    store.removeToken(token);
    try std.testing.expectEqual(@as(usize, 0), store.tokens.count());
}

test "requiresCsrfProtection detects state-changing methods" {
    try std.testing.expect(requiresCsrfProtection(.POST));
    try std.testing.expect(requiresCsrfProtection(.PUT));
    try std.testing.expect(requiresCsrfProtection(.PATCH));
    try std.testing.expect(requiresCsrfProtection(.DELETE));
    try std.testing.expect(!requiresCsrfProtection(.GET));
    try std.testing.expect(!requiresCsrfProtection(.HEAD));
    try std.testing.expect(!requiresCsrfProtection(.OPTIONS));
}

test "cleanupExpired removes expired tokens" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    const token = try store.generateToken("session1");

    // Manually expire the token
    store.mutex.lock();
    var entry = store.tokens.getPtr(token).?;
    entry.expires_at = std.time.milliTimestamp() - 1000; // 1 second ago
    store.mutex.unlock();

    store.cleanupExpired();
    try std.testing.expectEqual(@as(usize, 0), store.tokens.count());
}

test "cleanupExpired keeps valid tokens" {
    const allocator = std.testing.allocator;
    var store = CsrfStore.init(allocator);
    defer store.deinit();

    _ = try store.generateToken("session1");
    store.cleanupExpired();
    try std.testing.expectEqual(@as(usize, 1), store.tokens.count());
}
