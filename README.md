# Smithers v2

The ultimate UX for agentic coding. A native macOS IDE that feels like a TUI but has the power of a GUI.

## Build

Requires [Zig](https://ziglang.org/).

```bash
zig build          # Build everything
zig build run      # Build + run CLI
zig build test     # Run tests
zig build all      # Build + tests + fmt/lint checks
zig build xcframework  # Build dist/SmithersKit.xcframework (arm64+x86_64)
```

Notes:
- `zig build all` uses a single xcframework writer path. `xcode-build` consumes the already-built `dist/SmithersKit.xcframework` via build-step ordering.
- The Xcode verify phase checks for the xcframework and fails with guidance if missing; it does not trigger an implicit rebuild.

## Web App

Requires pnpm and Node.js.

```bash
cd web
pnpm install
pnpm dev          # Dev server at http://127.0.0.1:5173
pnpm build        # Production build to web/dist/
```

Or via Zig:

```bash
zig build web     # Build web app (requires pnpm)
```

## Project Structure

- `src/` — Zig core (libsmithers)
- `macos/` — Swift/SwiftUI native app
- `web/` — SolidJS web app
- `pkg/` — Vendored C/C++ dependencies
- `include/` — C API header
- `dist/` — Build artifacts (e.g., SmithersKit.xcframework)
- `submodules/` — Git submodules (Codex fork, JJ fork)
- `scripts/` — Automation and workflow tooling

## Using SmithersKit.xcframework in Xcode

1. Build the framework: `zig build xcframework` (outputs to `dist/SmithersKit.xcframework`).
2. In Xcode, drag `dist/SmithersKit.xcframework` into your project (Embed & Sign not required for static libs).
3. In Swift, a bridging header is only needed if mixing Objective‑C(++) — Xcode exposes C headers from xcframeworks automatically. You can also use a module map.
4. Linker: the xcframework archive bundles compiler-rt and SQLite. If you consume the raw Zig static library from `zig-out/`, you may need to link these yourself.
5. Minimum macOS: 14.0 (Sonoma). For manual `clang` link tests add `-mmacosx-version-min=14.0` to silence ld warnings.

## License

[MIT](LICENSE)
