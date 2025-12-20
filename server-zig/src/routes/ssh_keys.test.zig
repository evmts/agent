//! Unit tests for SSH key routes

const std = @import("std");
const testing = std.testing;
const ssh_keys = @import("ssh_keys.zig");

test "calculateFingerprint - valid RSA key" {
    const allocator = testing.allocator;
    const public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC user@example.com";

    // This should not error, but the actual fingerprint value depends on the key
    const fingerprint = try ssh_keys.calculateFingerprint(allocator, public_key);
    defer allocator.free(fingerprint);

    try testing.expect(std.mem.startsWith(u8, fingerprint, "SHA256:"));
}

test "calculateFingerprint - invalid key format" {
    const allocator = testing.allocator;
    const public_key = "invalid-key";

    const result = ssh_keys.calculateFingerprint(allocator, public_key);
    try testing.expectError(error.InvalidKeyFormat, result);
}

test "parseKeyType - ssh-rsa" {
    const public_key = "ssh-rsa AAAAB3NzaC1yc2E... user@host";
    const key_type = try ssh_keys.parseKeyType(public_key);
    try testing.expectEqualStrings("ssh-rsa", key_type);
}

test "parseKeyType - ssh-ed25519" {
    const public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@host";
    const key_type = try ssh_keys.parseKeyType(public_key);
    try testing.expectEqualStrings("ssh-ed25519", key_type);
}

test "parseKeyType - invalid format" {
    const public_key = "";
    const result = ssh_keys.parseKeyType(public_key);
    try testing.expectError(error.InvalidKeyFormat, result);
}

test "isValidKeyType - valid types" {
    try testing.expect(ssh_keys.isValidKeyType("ssh-rsa"));
    try testing.expect(ssh_keys.isValidKeyType("ssh-ed25519"));
    try testing.expect(ssh_keys.isValidKeyType("ecdsa-sha2-nistp256"));
    try testing.expect(ssh_keys.isValidKeyType("ecdsa-sha2-nistp384"));
    try testing.expect(ssh_keys.isValidKeyType("ecdsa-sha2-nistp521"));
}

test "isValidKeyType - invalid types" {
    try testing.expect(!ssh_keys.isValidKeyType("ssh-dss"));
    try testing.expect(!ssh_keys.isValidKeyType("invalid"));
    try testing.expect(!ssh_keys.isValidKeyType(""));
}
