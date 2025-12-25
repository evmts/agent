# Cryptography

Cryptographic primitives for SIWE authentication and key management.

## Key Files

| File | Purpose |
|------|---------|
| `secp256k1.zig` | Secp256k1 elliptic curve operations for Ethereum signatures |

## Features

- ECDSA signature verification for Ethereum addresses
- Public key recovery from signatures
- Keccak-256 hashing for Ethereum address derivation
- Used by SIWE (Sign-In With Ethereum) authentication

## Architecture

```
┌────────────────────────────────────────────────────┐
│              Cryptography Module                   │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │           secp256k1.zig                      │ │
│  │                                              │ │
│  │  • Signature verification                   │ │
│  │  • Public key recovery                      │ │
│  │  • Ethereum address derivation              │ │
│  │  • Keccak-256 hashing                       │ │
│  └──────────────────────────────────────────────┘ │
│                      │                            │
│                      ▼                            │
│           Used by lib/siwe.zig                    │
│         (Sign-In With Ethereum)                   │
└────────────────────────────────────────────────────┘
```

## Usage

```zig
const crypto = @import("crypto/secp256k1.zig");

// Verify Ethereum signature
const recovered_address = try crypto.recoverAddress(
    message_hash,
    signature,
    recovery_id,
);

// Verify matches expected address
if (!std.mem.eql(u8, &recovered_address, &expected_address)) {
    return error.InvalidSignature;
}
```
