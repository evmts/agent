# Contributing to Plue

**A multi-agent coding assistant built with Swift and Zig**

This guide will help you get from zero to running the app locally and building optimized production releases using Nix.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Build Commands](#build-commands)
- [Development Workflow](#development-workflow)
- [Production Builds](#production-builds)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Architecture Overview](#architecture-overview)
- [Contributing Guidelines](#contributing-guidelines)

## Prerequisites

### Install Nix

Plue uses Nix for reproducible development environments and builds. Install Nix using the Determinate Nix Installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

**Why Nix?**
- Reproducible builds across all machines
- Isolated development environment with exact dependency versions
- No need to manually install Swift, Zig, or macOS frameworks
- Production builds are bit-for-bit identical

### System Requirements

- **macOS 13.0+** (Ventura or later)
- **Intel or Apple Silicon Mac**
- **Nix with flakes enabled** (handled by Determinate installer)

## Development Setup

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/plue.git
cd plue
```

### 2. Enter Development Environment

```bash
nix develop
```

This automatically provides:
- Swift toolchain (latest stable)
- Zig compiler (v0.14.1)
- macOS frameworks (Foundation, AppKit, WebKit, Security, CoreServices)
- Development tools (git, curl, jq, pkg-config)
- Zig dependencies via zon2nix

**Environment Ready!** You'll see:
```
🚀 Plue development environment
Available commands:
  zig build        - Build complete project (Zig + Swift)
  zig build run    - Build and run Swift application
  zig build swift  - Build complete project (Zig + Swift)
  nix build        - Build with Nix

Environment ready!
```

### 3. First Build

```bash
# Build the complete project (Zig libraries + Swift app)
zig build

# Build and run the application
zig build run
```

The app will launch and you can start using Plue!

## Build Commands

### Core Build Commands

| Command | Description | Use Case |
|---------|-------------|----------|
| `zig build` | Build complete project (Zig + Swift) | Default development build |
| `zig build run` | Build and run Swift application | Development testing |
| `zig build swift` | Build complete project (explicit) | Same as `zig build` |
| `nix build` | Build with Nix packaging | Production/deployment builds |
| `nix run` | Build and run via Nix | Testing Nix package |

### Testing Commands

| Command | Description |
|---------|-------------|
| `zig build test` | Run all tests (unit + integration) |
| `zig build test-integration` | Run integration tests only |
| `zig build test-libplue` | Run libplue tests only |
| `zig build test-farcaster` | Run farcaster tests only |

### Manual Build Commands

```bash
# If you need to build Swift directly (rarely needed)
swift build --configuration release

# Build Zig libraries only
zig build-lib src/libplue.zig
```

## Development Workflow

### Quick Development Cycle

1. **Enter environment**: `nix develop` (if not already in)
2. **Make changes** to Swift code in `Sources/plue/` or Zig code in `src/`
3. **Build and test**: `zig build run`
4. **Run tests**: `zig build test`
5. **Repeat** as needed

### Architecture-Aware Development

Plue uses a **hybrid Swift-Zig architecture**:

- **Swift Layer** (`Sources/plue/`): UI, user interaction, SwiftUI views
- **Zig Layer** (`src/`): Business logic, state management, performance-critical code
- **FFI Bridge**: C-compatible interface between Swift and Zig

**Key Principle**: Zig owns the canonical application state, Swift is the presentation layer.

### Making Changes

#### Swift UI Changes
```bash
# Edit Swift files
vim Sources/plue/ContentView.swift

# Build and run to see changes
zig build run
```

#### Zig Backend Changes
```bash
# Edit Zig files
vim src/libplue.zig

# Build and test
zig build test
zig build run
```

#### Adding Dependencies

**Zig Dependencies** (edit `build.zig.zon`):
```bash
# After editing build.zig.zon, rebuild
nix develop --refresh  # Updates zon2nix cache
zig build
```

**Swift Dependencies** (edit `Package.swift`):
```bash
# Dependencies are automatically handled by the build system
zig build swift
```

## Production Builds

### Optimized Production Build

```bash
# Nix production build (recommended)
nix build

# The optimized binary is in result/bin/plue
./result/bin/plue

# Or run directly
nix run
```

### Install CLI Command

For VSCode-like CLI usage (`plue /path/to/project`):

```bash
# Install globally
./scripts/install.sh

# Usage examples
plue                    # Open in current directory
plue ~/my-project      # Open in specific directory
plue .                 # Open in current directory (explicit)
```

### Distribution

The Nix build produces a self-contained binary suitable for distribution:

```bash
# Copy binary from Nix build
cp result/bin/plue ./plue-dist

# Or use the Swift build output
cp .build/release/plue ./plue-dist
```

## Testing

### Test Suite

```bash
# Run all tests
zig build test

# Individual test suites
zig build test-integration    # Integration tests
zig build test-libplue       # Core library tests  
zig build test-farcaster     # Farcaster protocol tests
```

### Test Coverage

- **Unit Tests**: Core Zig functionality (`test/*.zig`)
- **Integration Tests**: Swift-Zig FFI integration
- **Manual Testing**: UI components and user workflows

### Continuous Integration

GitHub Actions automatically:
- Builds the project on every push/PR
- Runs the complete test suite
- Tests both development and production builds
- Validates Nix reproducibility

## Troubleshooting

### Common Issues

#### Nix Development Environment

```bash
# If environment seems stale
nix develop --refresh

# If flake is outdated
nix flake update
nix develop
```

#### Build Failures

```bash
# Clean Zig cache
rm -rf zig-out zig-cache .zig-cache

# Clean Swift build
rm -rf .build

# Full clean rebuild
nix develop --refresh
zig build
```

#### Swift/Zig Integration Issues

```bash
# Ensure Zig libraries are built first
zig build-lib src/libplue.zig
zig build-lib src/farcaster.zig

# Then build Swift
zig build swift
```

### Getting Help

1. **Check the logs**: Build output usually shows the exact error
2. **Verify environment**: Ensure you're in `nix develop`
3. **Clean builds**: Try cleaning and rebuilding from scratch
4. **Test incrementally**: Test Zig and Swift builds separately

## Architecture Overview

### File Structure

```
plue/
├── Sources/plue/           # Swift UI layer
│   ├── App.swift          # SwiftUI app entry point
│   ├── ContentView.swift  # Main UI layout
│   ├── PlueCore.swift     # Zig interface wrapper
│   └── ...                # UI components
├── src/                   # Zig backend layer
│   ├── libplue.zig       # Swift FFI interface
│   ├── farcaster.zig     # Protocol implementation
│   ├── core/             # Core business logic
│   └── ...
├── build.zig             # Zig build system (orchestrates everything)
├── Package.swift         # Swift package definition
├── flake.nix             # Nix development environment
└── scripts/              # Build and install scripts
```

### Build Process Flow

1. **Nix environment** provides Swift + Zig + dependencies
2. **Zig build system** coordinates the entire build:
   - Builds Zig libraries (`libplue`, `farcaster`)
   - Installs libraries to build directory
   - Invokes Swift build with proper linking
   - Creates final executable

### Key Design Principles

- **Single source of truth**: Zig manages canonical application state
- **Clean separation**: Swift handles UI, Zig handles logic
- **Performance-first**: Critical paths in Zig for speed
- **Memory safety**: Both languages provide memory safety guarantees

## Contributing Guidelines

### Code Style

**Swift Code**:
- Follow Swift API Design Guidelines
- Use SwiftUI best practices for reactive UI
- Keep business logic thin - delegate to Zig

**Zig Code**:
- Follow Zig style guide
- Use arena allocators for request/response cycles
- Export C-compatible functions for Swift FFI
- Comprehensive error handling with error unions

### Commit Guidelines

- Use conventional commits: `feat:`, `fix:`, `refactor:`, etc.
- Test changes with `zig build test` before committing
- Ensure both development and production builds work

### Pull Request Process

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/my-feature`
3. **Make changes and test**: `zig build test && zig build run`
4. **Commit with clear messages**
5. **Push and create PR**
6. **Ensure CI passes**

### Development Best Practices

- **Use the Nix environment** for all development
- **Test both Swift and Zig changes** thoroughly
- **Follow the hybrid architecture** - don't duplicate logic across layers
- **Document FFI changes** - Swift-Zig integration can be complex
- **Performance-test critical paths** - maintain the speed advantage

---

**Ready to contribute?** Jump into `nix develop` and start building! 🚀

For questions or issues, please open a GitHub issue or discussion.