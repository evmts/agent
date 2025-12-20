# Plue Zig Server

High-performance alternative server implementation for Plue, written in Zig.

## Overview

This is an experimental Zig implementation of the Plue API server. It provides the same functionality as the main TypeScript/Hono server but with:

- Lower memory footprint
- Faster cold starts
- Native performance for compute-intensive operations
- Direct integration with Voltaire EVM primitives

## Status

**Experimental** - Not yet production-ready. The TypeScript server remains the primary implementation.

## Features

- HTTP server using httpz (Zig HTTP library)
- PostgreSQL connection pooling
- Auth middleware (session-based authentication)
- Rate limiting middleware
- SIWE (Sign-In With Ethereum) support via secp256k1

## Structure

```
server-zig/
├── src/
│   ├── main.zig           # Server entry point
│   ├── config.zig         # Environment configuration
│   ├── routes.zig         # Route configuration (not shown)
│   ├── lib/
│   │   └── db.zig         # Database pool management
│   ├── crypto/
│   │   └── secp256k1.zig  # Ethereum signature verification
│   ├── middleware/
│   │   ├── auth.zig       # Authentication middleware
│   │   └── rate_limit.zig # Rate limiting
│   └── routes/
│       ├── auth.zig       # Auth endpoints
│       └── users.zig      # User endpoints
└── voltaire/              # EVM primitives library (git submodule)
```

## Building

```bash
# Build the server
cd server-zig
zig build

# Run in development
zig build run

# Run tests
zig build test
```

## Configuration

Environment variables:

- `DATABASE_URL` - PostgreSQL connection string
- `HOST` - Server host (default: 127.0.0.1)
- `PORT` - Server port (default: 3001)
- `NODE_ENV` - Environment (development/production)

## Voltaire Integration

The server includes [Voltaire](./voltaire/), an Ethereum primitives library providing:

- RLP encoding/decoding
- Keccak256 hashing
- secp256k1 signatures
- Address utilities
- Transaction types

This allows the Zig server to perform Ethereum operations natively without external dependencies.

## When to Use

Consider the Zig server when:

- Running on resource-constrained environments
- Need native EVM primitives performance
- Building edge deployments with minimal cold starts
- Require memory-safe concurrent request handling

For most use cases, the TypeScript server is recommended as it:

- Has complete feature parity
- Is easier to modify and extend
- Has better tooling and debugging support
- Integrates more easily with the Node.js ecosystem

## Development

To work on the Zig server:

1. Install Zig (0.13.0+)
2. Clone with submodules: `git clone --recursive`
3. Set up PostgreSQL and configure `DATABASE_URL`
4. Run `zig build run`

## Future Plans

- [ ] Complete API parity with TypeScript server
- [ ] WebSocket support for real-time features
- [ ] Performance benchmarks vs TypeScript implementation
- [ ] Production deployment documentation
