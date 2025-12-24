//! PROXY Protocol v1 Parser
//!
//! Parses the PROXY protocol v1 header sent by Cloudflare Spectrum.
//! This allows the SSH server to see the real client IP address instead
//! of Cloudflare's proxy IP.
//!
//! PROXY protocol v1 format:
//! "PROXY TCP4 <src_ip> <dst_ip> <src_port> <dst_port>\r\n"
//!
//! Reference: https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt

const std = @import("std");

const log = std.log.scoped(.proxy_protocol);

/// Protocol type
pub const Protocol = enum {
    tcp4,
    tcp6,
    unknown,
};

/// Parsed PROXY protocol information
pub const ProxyInfo = struct {
    /// Original client IP address (as string)
    client_ip: []const u8,
    /// Original client port
    client_port: u16,
    /// Destination IP address (as string)
    server_ip: []const u8,
    /// Destination port
    server_port: u16,
    /// Protocol type (TCP4, TCP6, UNKNOWN)
    protocol: Protocol,
    /// Total bytes consumed (including \r\n)
    header_length: usize,
};

/// Parse PROXY protocol v1 header from the beginning of a data buffer
///
/// Returns null if no valid PROXY header is found (connection may be direct)
pub fn parseProxyProtocolV1(data: []const u8) ?ProxyInfo {
    // Minimum header: "PROXY UNKNOWN\r\n" = 15 bytes
    if (data.len < 15) {
        return null;
    }

    // Check for PROXY prefix
    if (!std.mem.startsWith(u8, data, "PROXY ")) {
        return null;
    }

    // Find the end of the header (\r\n)
    const header_end = std.mem.indexOf(u8, data, "\r\n") orelse {
        // No complete header yet
        return null;
    };

    const header = data[6..header_end]; // Skip "PROXY "
    const header_length = header_end + 2; // Include \r\n

    // Parse protocol
    if (std.mem.startsWith(u8, header, "UNKNOWN")) {
        // UNKNOWN protocol - no address info
        return ProxyInfo{
            .client_ip = "",
            .client_port = 0,
            .server_ip = "",
            .server_port = 0,
            .protocol = .unknown,
            .header_length = header_length,
        };
    }

    // Parse TCP4 or TCP6
    const protocol: Protocol = if (std.mem.startsWith(u8, header, "TCP4 "))
        .tcp4
    else if (std.mem.startsWith(u8, header, "TCP6 "))
        .tcp6
    else {
        log.warn("Unknown PROXY protocol variant: {s}", .{header});
        return null;
    };

    // Skip "TCPx "
    const addr_part = header[5..];

    // Split by spaces: <src_ip> <dst_ip> <src_port> <dst_port>
    var parts = std.mem.splitScalar(u8, addr_part, ' ');

    const client_ip = parts.next() orelse return null;
    const server_ip = parts.next() orelse return null;
    const client_port_str = parts.next() orelse return null;
    const server_port_str = parts.next() orelse return null;

    const client_port = std.fmt.parseInt(u16, client_port_str, 10) catch {
        log.warn("Invalid client port in PROXY header: {s}", .{client_port_str});
        return null;
    };

    const server_port = std.fmt.parseInt(u16, server_port_str, 10) catch {
        log.warn("Invalid server port in PROXY header: {s}", .{server_port_str});
        return null;
    };

    return ProxyInfo{
        .client_ip = client_ip,
        .client_port = client_port,
        .server_ip = server_ip,
        .server_port = server_port,
        .protocol = protocol,
        .header_length = header_length,
    };
}

/// Check if data starts with PROXY protocol header
pub fn hasProxyHeader(data: []const u8) bool {
    return std.mem.startsWith(u8, data, "PROXY ");
}

// ============================================================================
// Tests
// ============================================================================

test "parse TCP4 PROXY header" {
    const data = "PROXY TCP4 192.168.1.100 10.0.0.1 54321 22\r\n";
    const info = parseProxyProtocolV1(data).?;

    try std.testing.expectEqualStrings("192.168.1.100", info.client_ip);
    try std.testing.expectEqualStrings("10.0.0.1", info.server_ip);
    try std.testing.expectEqual(@as(u16, 54321), info.client_port);
    try std.testing.expectEqual(@as(u16, 22), info.server_port);
    try std.testing.expectEqual(Protocol.tcp4, info.protocol);
    try std.testing.expectEqual(@as(usize, 44), info.header_length);
}

test "parse TCP6 PROXY header" {
    const data = "PROXY TCP6 2001:db8::1 2001:db8::2 54321 22\r\n";
    const info = parseProxyProtocolV1(data).?;

    try std.testing.expectEqualStrings("2001:db8::1", info.client_ip);
    try std.testing.expectEqualStrings("2001:db8::2", info.server_ip);
    try std.testing.expectEqual(Protocol.tcp6, info.protocol);
}

test "parse UNKNOWN PROXY header" {
    const data = "PROXY UNKNOWN\r\n";
    const info = parseProxyProtocolV1(data).?;

    try std.testing.expectEqualStrings("", info.client_ip);
    try std.testing.expectEqual(@as(u16, 0), info.client_port);
    try std.testing.expectEqual(Protocol.unknown, info.protocol);
}

test "reject non-PROXY data" {
    const data = "SSH-2.0-OpenSSH_8.0\r\n";
    const info = parseProxyProtocolV1(data);

    try std.testing.expect(info == null);
}

test "reject incomplete header" {
    const data = "PROXY TCP4 192.168.1.100";
    const info = parseProxyProtocolV1(data);

    try std.testing.expect(info == null);
}

test "hasProxyHeader" {
    try std.testing.expect(hasProxyHeader("PROXY TCP4 1.2.3.4 5.6.7.8 1234 22\r\n"));
    try std.testing.expect(!hasProxyHeader("SSH-2.0-OpenSSH\r\n"));
    try std.testing.expect(!hasProxyHeader(""));
}

test "header with trailing data" {
    const data = "PROXY TCP4 1.2.3.4 5.6.7.8 1234 22\r\nSSH-2.0-OpenSSH\r\n";
    const info = parseProxyProtocolV1(data).?;

    try std.testing.expectEqualStrings("1.2.3.4", info.client_ip);
    try std.testing.expectEqual(@as(usize, 36), info.header_length);

    // Verify remaining data can be accessed
    const remaining = data[info.header_length..];
    try std.testing.expect(std.mem.startsWith(u8, remaining, "SSH-2.0-OpenSSH"));
}
