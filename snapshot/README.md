# Snapshot

Node.js/Bun native bindings for Jujutsu (jj) version control system.

## Purpose

Provides TypeScript/JavaScript access to jj-lib (Jujutsu's Rust core library) via napi-rs. Used by the server's Git subsystem to read repository history, snapshots, and file contents without shelling out to the jj CLI.

## Key Files

| File | Description |
|------|-------------|
| `Cargo.toml` | Rust package manifest with napi bindings |
| `build.rs` | napi-rs build script |
| `src/lib.rs` | Rust implementation with napi exports |
| `src/snapshot.ts` | TypeScript wrapper API |
| `src/snapshot.test.ts` | Test suite |
| `index.js` | CommonJS entry point |
| `index.mjs` | ES Module entry point |
| `index.d.ts` | TypeScript type definitions |
| `jj-native.darwin-arm64.node` | Compiled native binary |

## Dependencies

| Dependency | Purpose |
|-----------|---------|
| `napi` + `napi-derive` | Node.js native bindings |
| `jj-lib` (v0.36.0) | Jujutsu core library |
| `tokio` | Async runtime |
| `serde` + `serde_json` | Serialization |

## API

TypeScript API surface:

```typescript
// Open a jj workspace
const workspace = await openWorkspace('/path/to/repo');

// Get commit info
const commit = await workspace.getCommit('commit-id');

// List file changes
const changes = await workspace.getFileChanges('commit-id');

// Read file content at commit
const content = await workspace.getFileContent('commit-id', 'path/to/file');

// Get commit history
const history = await workspace.getHistory('commit-id', { limit: 100 });
```

## Build

```bash
# Build native module
cargo build --release

# Run tests
npm test
```

## Platform Support

Currently built for:
- macOS ARM64 (`darwin-arm64`)

Additional platforms require compilation:
- Linux x64 (`linux-x64`)
- Linux ARM64 (`linux-arm64`)
- Windows x64 (`win32-x64`)
