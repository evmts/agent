# Plue

**A multi-agent coding assistant built with Swift and Zig**

Plue is a native macOS application that provides an intelligent coding assistant interface with multiple interaction modes. It combines a modern Swift UI with high-performance Zig backend libraries to deliver a responsive and powerful development tool.

## Features

- **🎯 Vim-style Prompt Interface** - Efficient text input with vim keybindings
- **💬 Modern Chat Interface** - Conversational AI interaction
- **🖥️ Terminal Integration** - Built-in terminal functionality  
- **🌐 Farcaster Integration** - Social coding features
- **⚡ High Performance** - Zig backend for optimal performance
- **🍎 Native macOS** - Built specifically for macOS with native frameworks

<img width="999" alt="image" src="https://github.com/user-attachments/assets/b515f123-1243-4e8a-97ef-62763838adf2" />

## Architecture

Plue uses a hybrid architecture:

- **Swift Frontend** - Native macOS UI using SwiftUI, providing smooth user experience
- **Zig Backend** - High-performance core libraries written in Zig for:
  - Terminal emulation and vim functionality
  - Farcaster protocol implementation
  - Core processing logic
- **Unified Build System** - Integrated build process using Zig as the orchestrator

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Nix** - For reproducible builds and development environment

## Quick Start

### 1. Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone and Enter Development Environment

```bash
git clone <repository-url>
cd plue
nix develop
```

### 3. Build and Run

```bash
# Build the complete project (Zig libraries + Swift application)
zig build

# Build and run the application
zig build run
```

## Development Workflow

### Using Nix + Zig (Recommended)

```bash
# Enter the development environment
nix develop

# Available commands inside the environment:
zig build        # Build complete project (Zig + Swift)
zig build run    # Build and run Swift application  
zig build swift  # Build complete project (explicit)
zig build test   # Run unit tests

# For production builds
nix build        # Build with Nix for deployment
```

### Build Commands

| Command | Description |
|---------|-------------|
| `zig build` | Build complete project (default) |
| `zig build run` | Build and run the Swift application |
| `zig build swift` | Build complete project (explicit) |
| `zig build test` | Run unit tests |
| `zig build run-swift` | Build and run Swift app (explicit) |

## Project Structure

```
plue/
├── Sources/plue/           # Swift application source
│   ├── App.swift          # Main application entry
│   ├── ContentView.swift  # Primary UI view
│   ├── VimPromptView.swift # Vim-style interface
│   ├── ModernChatView.swift # Chat interface  
│   ├── TerminalView.swift  # Terminal component
│   └── ...
├── src/                   # Zig backend libraries
│   ├── libplue.zig       # Core Swift interop library
│   ├── farcaster.zig     # Farcaster protocol implementation
│   └── ...
├── build.zig             # Zig build configuration
├── Package.swift         # Swift package configuration
├── flake.nix             # Nix development environment
└── .github/workflows/    # CI/CD configuration
```

## Development Environment

The Nix development environment provides:

- **Swift** - Latest Swift toolchain
- **Zig** - Zig compiler and build system
- **macOS Frameworks** - Foundation, AppKit, WebKit, Security
- **Development Tools** - Git, curl, jq, pkg-config

All dependencies are automatically managed and pinned for reproducible builds.

## Building

### Local Development

```bash
nix develop    # Enter environment
zig build      # Build everything
zig build run  # Run the application
```

### Production/CI

```bash
nix build      # Reproducible production build
nix run        # Run the built application
```

### Manual Swift Build (if needed)

```bash
# If you need to build Swift directly
swift build --configuration release
```

## Contributing

1. **Enter the development environment**: `nix develop`
2. **Make your changes** to Swift or Zig code
3. **Test your changes**: `zig build test`
4. **Build and verify**: `zig build run`
5. **Submit a pull request**

## CI/CD

The project uses GitHub Actions with Nix for:

- **Automated builds** on every push and PR
- **Reproducible environments** across all build machines  
- **Dependency updates** via Dependabot
- **Cross-platform compatibility** testing

## License

[Add your license here]

## Support

[Add support information here]
