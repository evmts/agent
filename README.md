# Smithers v2

The ultimate UX for agentic coding. A native macOS IDE that feels like a TUI but has the power of a GUI.

## Build

Requires [Zig](https://ziglang.org/).

```bash
zig build          # Build everything
zig build run      # Build + run CLI
zig build test     # Run tests
zig build all      # Build + tests + fmt/lint checks
```

## Project Structure

- `src/` — Zig core (libsmithers)
- `macos/` — Swift/SwiftUI native app
- `web/` — SolidJS web app
- `pkg/` — Vendored C/C++ dependencies
- `include/` — C API header
- `submodules/` — Git submodules (Codex fork, JJ fork)
- `scripts/` — Automation and workflow tooling

## License

[MIT](LICENSE)
