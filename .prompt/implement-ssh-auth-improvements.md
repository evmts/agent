# Implement SSH Authentication Improvements

## Priority: Low

## Problem
The SSH authentication system in `src/ssh/auth.zig` has several TODO comments indicating incomplete functionality, particularly around signature verification, full protocol handling, and advanced key management features.

## Current Missing Features

### 1. SSH Signature Verification
```zig
// TODO in src/ssh/auth.zig around line 150:
pub fn verifySignature(self: *PublicKey, message: []const u8, signature: []const u8) !bool {
    _ = self;
    _ = message;
    _ = signature;
    // TODO: Implement proper SSH signature verification
    return false;
}
```

### 2. Certificate-based Authentication
```zig
// TODO: Support SSH certificates
pub fn parseCertificate(data: []const u8) !Certificate {
    // Parse SSH certificate format
    // Verify certificate chain
    // Extract principals and validity
}
```

### 3. Advanced Key Formats
```zig
// TODO: Support additional key formats like ECDSA P-521, Ed448
```

## Expected Implementation

### 1. SSH Signature Verification
```zig
pub fn verifySignature(self: *PublicKey, allocator: std.mem.Allocator, message: []const u8, signature: []const u8) !bool {
    switch (self.key_type) {
        .rsa => {
            return try self.verifyRSASignature(allocator, message, signature);
        },
        .ed25519 => {
            return try self.verifyEd25519Signature(message, signature);
        },
        .ecdsa_p256 => {
            return try self.verifyECDSASignature(allocator, message, signature, .p256);
        },
        .ecdsa_p384 => {
            return try self.verifyECDSASignature(allocator, message, signature, .p384);
        },
        .ecdsa_p521 => {
            return try self.verifyECDSASignature(allocator, message, signature, .p521);
        },
    }
}

fn verifyRSASignature(self: *PublicKey, allocator: std.mem.Allocator, message: []const u8, signature: []const u8) !bool {
    // Parse SSH signature format
    var reader = std.io.fixedBufferStream(signature);
    const sig_reader = reader.reader();
    
    // Read signature algorithm name
    const alg_len = try sig_reader.readIntBig(u32);
    if (alg_len > 64) return error.InvalidSignature;
    
    const alg_name = try allocator.alloc(u8, alg_len);
    defer allocator.free(alg_name);
    try sig_reader.readNoEof(alg_name);
    
    // Verify algorithm matches key type
    if (!std.mem.eql(u8, alg_name, "rsa-sha2-256") and !std.mem.eql(u8, alg_name, "rsa-sha2-512")) {
        return error.UnsupportedAlgorithm;
    }
    
    // Read signature blob
    const sig_len = try sig_reader.readIntBig(u32);
    if (sig_len > 1024) return error.InvalidSignature;
    
    const sig_blob = try allocator.alloc(u8, sig_len);
    defer allocator.free(sig_blob);
    try sig_reader.readNoEof(sig_blob);
    
    // Hash the message
    var hasher = if (std.mem.eql(u8, alg_name, "rsa-sha2-512"))
        std.crypto.hash.sha2.Sha512.init(.{})
    else
        std.crypto.hash.sha2.Sha256.init(.{});
    
    hasher.update(message);
    const message_hash = hasher.finalResult();
    
    // Parse RSA public key from self.key_data
    const rsa_key = try parseRSAPublicKey(allocator, self.key_data);
    defer rsa_key.deinit(allocator);
    
    // Verify RSA signature
    return try rsa_key.verify(allocator, &message_hash, sig_blob, if (std.mem.eql(u8, alg_name, "rsa-sha2-512")) .sha512 else .sha256);
}

fn verifyEd25519Signature(self: *PublicKey, message: []const u8, signature: []const u8) !bool {
    // Parse SSH signature format
    var reader = std.io.fixedBufferStream(signature);
    const sig_reader = reader.reader();
    
    // Read algorithm name
    const alg_len = try sig_reader.readIntBig(u32);
    if (alg_len != 11) return error.InvalidSignature;
    
    var alg_name: [11]u8 = undefined;
    try sig_reader.readNoEof(&alg_name);
    
    if (!std.mem.eql(u8, &alg_name, "ssh-ed25519")) {
        return error.UnsupportedAlgorithm;
    }
    
    // Read signature blob
    const sig_len = try sig_reader.readIntBig(u32);
    if (sig_len != 64) return error.InvalidSignature;
    
    var sig_blob: [64]u8 = undefined;
    try sig_reader.readNoEof(&sig_blob);
    
    // Extract Ed25519 public key (32 bytes)
    if (self.key_data.len < 32) return error.InvalidKey;
    const public_key = self.key_data[self.key_data.len - 32..];
    
    // Verify signature using Ed25519
    const pub_key = std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key[0..32].*) catch return error.InvalidKey;
    const signature_ed25519 = std.crypto.sign.Ed25519.Signature.fromBytes(sig_blob) catch return error.InvalidSignature;
    
    signature_ed25519.verify(message, pub_key) catch return false;
    return true;
}

fn verifyECDSASignature(self: *PublicKey, allocator: std.mem.Allocator, message: []const u8, signature: []const u8, curve: enum { p256, p384, p521 }) !bool {
    // Parse SSH signature format
    var reader = std.io.fixedBufferStream(signature);
    const sig_reader = reader.reader();
    
    // Read algorithm name
    const alg_len = try sig_reader.readIntBig(u32);
    const expected_alg = switch (curve) {
        .p256 => "ecdsa-sha2-nistp256",
        .p384 => "ecdsa-sha2-nistp384", 
        .p521 => "ecdsa-sha2-nistp521",
    };
    
    if (alg_len != expected_alg.len) return error.InvalidSignature;
    
    const alg_name = try allocator.alloc(u8, alg_len);
    defer allocator.free(alg_name);
    try sig_reader.readNoEof(alg_name);
    
    if (!std.mem.eql(u8, alg_name, expected_alg)) {
        return error.UnsupportedAlgorithm;
    }
    
    // Read signature blob (DER-encoded ECDSA signature)
    const sig_len = try sig_reader.readIntBig(u32);
    const sig_blob = try allocator.alloc(u8, sig_len);
    defer allocator.free(sig_blob);
    try sig_reader.readNoEof(sig_blob);
    
    // Hash message with appropriate algorithm
    const message_hash = switch (curve) {
        .p256 => blk: {
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update(message);
            break :blk hasher.finalResult();
        },
        .p384 => blk: {
            var hasher = std.crypto.hash.sha2.Sha384.init(.{});
            hasher.update(message);
            break :blk hasher.finalResult();
        },
        .p521 => blk: {
            var hasher = std.crypto.hash.sha2.Sha512.init(.{});
            hasher.update(message);
            break :blk hasher.finalResult();
        },
    };
    
    // Parse ECDSA public key and verify signature
    return try verifyECDSAWithCurve(allocator, self.key_data, &message_hash, sig_blob, curve);
}
```

### 2. SSH Certificate Support
```zig
pub const Certificate = struct {
    nonce: []const u8,
    public_key: PublicKey,
    serial: u64,
    cert_type: CertificateType,
    key_id: []const u8,
    valid_principals: [][]const u8,
    valid_after: u64,
    valid_before: u64,
    critical_options: std.StringHashMap([]const u8),
    extensions: std.StringHashMap([]const u8),
    signature_key: PublicKey,
    signature: []const u8,
    
    pub fn deinit(self: *Certificate, allocator: std.mem.Allocator) void {
        allocator.free(self.nonce);
        self.public_key.deinit(allocator);
        allocator.free(self.key_id);
        for (self.valid_principals) |principal| {
            allocator.free(principal);
        }
        allocator.free(self.valid_principals);
        
        var crit_iter = self.critical_options.iterator();
        while (crit_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.critical_options.deinit();
        
        var ext_iter = self.extensions.iterator();
        while (ext_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.extensions.deinit();
        
        self.signature_key.deinit(allocator);
        allocator.free(self.signature);
    }
};

pub const CertificateType = enum(u32) {
    user = 1,
    host = 2,
};

pub fn parseCertificate(allocator: std.mem.Allocator, data: []const u8) !Certificate {
    var reader = std.io.fixedBufferStream(data);
    const cert_reader = reader.reader();
    
    // Read certificate type
    const type_len = try cert_reader.readIntBig(u32);
    const cert_type_str = try allocator.alloc(u8, type_len);
    defer allocator.free(cert_type_str);
    try cert_reader.readNoEof(cert_type_str);
    
    // Verify certificate type
    const is_user_cert = std.mem.endsWith(u8, cert_type_str, "-cert-v01@openssh.com");
    if (!is_user_cert) return error.UnsupportedCertificateType;
    
    // Read nonce
    const nonce_len = try cert_reader.readIntBig(u32);
    const nonce = try allocator.alloc(u8, nonce_len);
    errdefer allocator.free(nonce);
    try cert_reader.readNoEof(nonce);
    
    // Read public key
    const pubkey_len = try cert_reader.readIntBig(u32);
    const pubkey_data = try allocator.alloc(u8, pubkey_len);
    defer allocator.free(pubkey_data);
    try cert_reader.readNoEof(pubkey_data);
    
    // Parse the embedded public key
    const public_key = try PublicKey.parseFromBytes(allocator, pubkey_data);
    errdefer public_key.deinit(allocator);
    
    // Read serial number
    const serial = try cert_reader.readIntBig(u64);
    
    // Read certificate type
    const cert_type_num = try cert_reader.readIntBig(u32);
    const cert_type = switch (cert_type_num) {
        1 => CertificateType.user,
        2 => CertificateType.host,
        else => return error.InvalidCertificateType,
    };
    
    // Read key ID
    const key_id_len = try cert_reader.readIntBig(u32);
    const key_id = try allocator.alloc(u8, key_id_len);
    errdefer allocator.free(key_id);
    try cert_reader.readNoEof(key_id);
    
    // Read valid principals
    const principals_len = try cert_reader.readIntBig(u32);
    const principals_data = try allocator.alloc(u8, principals_len);
    defer allocator.free(principals_data);
    try cert_reader.readNoEof(principals_data);
    
    const valid_principals = try parsePrincipals(allocator, principals_data);
    errdefer {
        for (valid_principals) |principal| allocator.free(principal);
        allocator.free(valid_principals);
    }
    
    // Read validity period
    const valid_after = try cert_reader.readIntBig(u64);
    const valid_before = try cert_reader.readIntBig(u64);
    
    // Read critical options
    const crit_opts_len = try cert_reader.readIntBig(u32);
    const crit_opts_data = try allocator.alloc(u8, crit_opts_len);
    defer allocator.free(crit_opts_data);
    try cert_reader.readNoEof(crit_opts_data);
    
    var critical_options = try parseOptions(allocator, crit_opts_data);
    errdefer {
        var iter = critical_options.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        critical_options.deinit();
    }
    
    // Read extensions
    const ext_len = try cert_reader.readIntBig(u32);
    const ext_data = try allocator.alloc(u8, ext_len);
    defer allocator.free(ext_data);
    try cert_reader.readNoEof(ext_data);
    
    var extensions = try parseOptions(allocator, ext_data);
    errdefer {
        var iter = extensions.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        extensions.deinit();
    }
    
    // Skip reserved field
    _ = try cert_reader.readIntBig(u32);
    
    // Read signature key
    const sig_key_len = try cert_reader.readIntBig(u32);
    const sig_key_data = try allocator.alloc(u8, sig_key_len);
    defer allocator.free(sig_key_data);
    try cert_reader.readNoEof(sig_key_data);
    
    const signature_key = try PublicKey.parseFromBytes(allocator, sig_key_data);
    errdefer signature_key.deinit(allocator);
    
    // Read signature
    const signature_len = try cert_reader.readIntBig(u32);
    const signature = try allocator.alloc(u8, signature_len);
    errdefer allocator.free(signature);
    try cert_reader.readNoEof(signature);
    
    return Certificate{
        .nonce = nonce,
        .public_key = public_key,
        .serial = serial,
        .cert_type = cert_type,
        .key_id = key_id,
        .valid_principals = valid_principals,
        .valid_after = valid_after,
        .valid_before = valid_before,
        .critical_options = critical_options,
        .extensions = extensions,
        .signature_key = signature_key,
        .signature = signature,
    };
}

pub fn verifyCertificate(cert: *Certificate, allocator: std.mem.Allocator, ca_keys: []PublicKey) !bool {
    // Check if certificate is signed by a trusted CA
    var is_trusted = false;
    for (ca_keys) |ca_key| {
        if (cert.signature_key.equals(&ca_key)) {
            is_trusted = true;
            break;
        }
    }
    
    if (!is_trusted) return error.UntrustedCA;
    
    // Check validity period
    const now = @as(u64, @intCast(std.time.timestamp()));
    if (now < cert.valid_after or now > cert.valid_before) {
        return error.CertificateExpired;
    }
    
    // Construct data to be signed (everything except signature)
    const tbs_cert = try buildToBeSigned(allocator, cert);
    defer allocator.free(tbs_cert);
    
    // Verify signature
    return try cert.signature_key.verifySignature(allocator, tbs_cert, cert.signature);
}
```

### 3. Advanced Key Format Support
```zig
pub const KeyType = enum {
    rsa,
    ed25519,
    ecdsa_p256,
    ecdsa_p384,
    ecdsa_p521,
    ed448,
    rsa_sha256,
    rsa_sha512,
};

pub fn parseKeyType(type_string: []const u8) !KeyType {
    if (std.mem.eql(u8, type_string, "ssh-rsa")) return .rsa;
    if (std.mem.eql(u8, type_string, "rsa-sha2-256")) return .rsa_sha256;
    if (std.mem.eql(u8, type_string, "rsa-sha2-512")) return .rsa_sha512;
    if (std.mem.eql(u8, type_string, "ssh-ed25519")) return .ed25519;
    if (std.mem.eql(u8, type_string, "ssh-ed448")) return .ed448;
    if (std.mem.eql(u8, type_string, "ecdsa-sha2-nistp256")) return .ecdsa_p256;
    if (std.mem.eql(u8, type_string, "ecdsa-sha2-nistp384")) return .ecdsa_p384;
    if (std.mem.eql(u8, type_string, "ecdsa-sha2-nistp521")) return .ecdsa_p521;
    
    return error.UnsupportedKeyType;
}

fn verifyEd448Signature(self: *PublicKey, message: []const u8, signature: []const u8) !bool {
    // Parse SSH signature format for Ed448
    var reader = std.io.fixedBufferStream(signature);
    const sig_reader = reader.reader();
    
    // Read algorithm name
    const alg_len = try sig_reader.readIntBig(u32);
    if (alg_len != 10) return error.InvalidSignature;
    
    var alg_name: [10]u8 = undefined;
    try sig_reader.readNoEof(&alg_name);
    
    if (!std.mem.eql(u8, &alg_name, "ssh-ed448")) {
        return error.UnsupportedAlgorithm;
    }
    
    // Read signature blob (114 bytes for Ed448)
    const sig_len = try sig_reader.readIntBig(u32);
    if (sig_len != 114) return error.InvalidSignature;
    
    var sig_blob: [114]u8 = undefined;
    try sig_reader.readNoEof(&sig_blob);
    
    // Extract Ed448 public key (57 bytes)
    if (self.key_data.len < 57) return error.InvalidKey;
    const public_key = self.key_data[self.key_data.len - 57..];
    
    // Verify signature using Ed448
    const pub_key = std.crypto.sign.Ed448.PublicKey.fromBytes(public_key[0..57].*) catch return error.InvalidKey;
    const signature_ed448 = std.crypto.sign.Ed448.Signature.fromBytes(sig_blob) catch return error.InvalidSignature;
    
    signature_ed448.verify(message, pub_key) catch return false;
    return true;
}
```

### 4. SSH Agent Protocol Support
```zig
pub const SSHAgent = struct {
    socket_path: []const u8,
    
    pub fn init(socket_path: []const u8) SSHAgent {
        return SSHAgent{
            .socket_path = socket_path,
        };
    }
    
    pub fn listKeys(self: *SSHAgent, allocator: std.mem.Allocator) ![]PublicKey {
        // Connect to SSH agent socket
        const socket = try std.net.connectUnixSocket(self.socket_path);
        defer socket.close();
        
        // Send SSH_AGENTC_REQUEST_IDENTITIES
        const request = [_]u8{ 0, 0, 0, 1, 11 }; // Length + SSH_AGENTC_REQUEST_IDENTITIES
        _ = try socket.writeAll(&request);
        
        // Read response
        var response_len_buf: [4]u8 = undefined;
        _ = try socket.readAll(&response_len_buf);
        const response_len = std.mem.readIntBig(u32, &response_len_buf);
        
        const response = try allocator.alloc(u8, response_len);
        defer allocator.free(response);
        _ = try socket.readAll(response);
        
        // Parse response
        if (response.len < 1 or response[0] != 12) { // SSH_AGENT_IDENTITIES_ANSWER
            return error.AgentError;
        }
        
        return try parseAgentKeys(allocator, response[1..]);
    }
    
    pub fn signData(self: *SSHAgent, allocator: std.mem.Allocator, public_key: *PublicKey, data: []const u8) ![]const u8 {
        const socket = try std.net.connectUnixSocket(self.socket_path);
        defer socket.close();
        
        // Build SSH_AGENTC_SIGN_REQUEST
        var request = std.ArrayList(u8).init(allocator);
        defer request.deinit();
        
        // Message type
        try request.append(13); // SSH_AGENTC_SIGN_REQUEST
        
        // Public key blob
        const key_blob = try public_key.toWireFormat(allocator);
        defer allocator.free(key_blob);
        try request.writer().writeIntBig(u32, @intCast(key_blob.len));
        try request.appendSlice(key_blob);
        
        // Data to sign
        try request.writer().writeIntBig(u32, @intCast(data.len));
        try request.appendSlice(data);
        
        // Flags
        try request.writer().writeIntBig(u32, 0);
        
        // Send request with length prefix
        const length_bytes = std.mem.asBytes(&std.mem.nativeToBig(u32, @intCast(request.items.len)));
        _ = try socket.writeAll(length_bytes);
        _ = try socket.writeAll(request.items);
        
        // Read response
        var response_len_buf: [4]u8 = undefined;
        _ = try socket.readAll(&response_len_buf);
        const response_len = std.mem.readIntBig(u32, &response_len_buf);
        
        const response = try allocator.alloc(u8, response_len);
        defer allocator.free(response);
        _ = try socket.readAll(response);
        
        if (response.len < 1 or response[0] != 14) { // SSH_AGENT_SIGN_RESPONSE
            return error.SigningFailed;
        }
        
        // Extract signature
        const sig_len = std.mem.readIntBig(u32, response[1..5]);
        return try allocator.dupe(u8, response[5..5 + sig_len]);
    }
};
```

## Helper Functions Needed
```zig
fn parseRSAPublicKey(allocator: std.mem.Allocator, key_data: []const u8) !RSAPublicKey {
    // Parse SSH wire format RSA key
    var reader = std.io.fixedBufferStream(key_data);
    const key_reader = reader.reader();
    
    // Read modulus
    const n_len = try key_reader.readIntBig(u32);
    const n = try allocator.alloc(u8, n_len);
    try key_reader.readNoEof(n);
    
    // Read exponent
    const e_len = try key_reader.readIntBig(u32);
    const e = try allocator.alloc(u8, e_len);
    try key_reader.readNoEof(e);
    
    return RSAPublicKey{
        .n = n,
        .e = e,
    };
}

fn parsePrincipals(allocator: std.mem.Allocator, data: []const u8) ![][]const u8 {
    var principals = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (principals.items) |principal| allocator.free(principal);
        principals.deinit();
    }
    
    var reader = std.io.fixedBufferStream(data);
    const principal_reader = reader.reader();
    
    while (reader.pos < data.len) {
        const len = try principal_reader.readIntBig(u32);
        const principal = try allocator.alloc(u8, len);
        try principal_reader.readNoEof(principal);
        try principals.append(principal);
    }
    
    return principals.toOwnedSlice();
}

fn parseOptions(allocator: std.mem.Allocator, data: []const u8) !std.StringHashMap([]const u8) {
    var options = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var iter = options.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        options.deinit();
    }
    
    var reader = std.io.fixedBufferStream(data);
    const option_reader = reader.reader();
    
    while (reader.pos < data.len) {
        // Read key
        const key_len = try option_reader.readIntBig(u32);
        const key = try allocator.alloc(u8, key_len);
        try option_reader.readNoEof(key);
        
        // Read value
        const value_len = try option_reader.readIntBig(u32);
        const value = try allocator.alloc(u8, value_len);
        try option_reader.readNoEof(value);
        
        try options.put(key, value);
    }
    
    return options;
}

fn buildToBeSigned(allocator: std.mem.Allocator, cert: *Certificate) ![]const u8 {
    // Build the certificate data that was signed (everything except signature)
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    
    // This would reconstruct the certificate fields in SSH wire format
    // up to but not including the signature
    
    return data.toOwnedSlice();
}
```

## Files to Modify
- `src/ssh/auth.zig` (implement signature verification and certificates)
- `src/ssh/agent.zig` (new file for SSH agent support) 
- `src/ssh/protocol.zig` (enhance protocol handling)
- Add cryptographic utilities for various algorithms

## Testing Requirements
- Test signature verification for all key types
- Test certificate parsing and validation
- Test SSH agent communication
- Test key format compatibility
- Test with real SSH clients and keys
- Security testing for signature verification
- Performance testing for cryptographic operations

## Dependencies
- Cryptographic libraries for RSA, ECDSA, Ed25519, Ed448
- SSH protocol specification knowledge
- SSH agent protocol implementation
- Certificate format specifications
- Base64 and ASN.1 parsing utilities

## Benefits
- Provides complete SSH authentication
- Supports modern cryptographic algorithms
- Enables certificate-based authentication
- Improves security and compatibility
- Essential for production SSH server