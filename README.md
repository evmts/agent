# Plue (under development)

**A multi-agent coding assistant built with Swift and Zig**

Plue is a native macOS application that provides an intelligent coding assistant interface with multiple interaction modes. It combines a modern Swift UI with high-performance Zig backend libraries to deliver a responsive and powerful development tool.

## Features

- **🎯 Vim-style Prompt Interface** - Efficient text input with vim keybindings
- **💬 Modern Chat Interface** - Conversational AI interaction
- **🖥️ Terminal Integration** - Built-in terminal functionality  
- **🌐 Farcaster Integration** - Social coding features
- **🔧 Agent Workflows** - Git worktree management and Dagger container integration
- **⚡ High Performance** - Zig backend for optimal performance
- **📂 Command Line Interface** - Open Plue from terminal like VSCode (`plue /path/to/project`)
- **🍎 Native macOS** - Built specifically for macOS with native frameworks

![telegram-cloud-photo-size-1-5073602166656183931-y](https://github.com/user-attachments/assets/94233eed-b09f-4ed0-a598-8de8c40e7ac4)
![telegram-cloud-photo-size-1-5073602166656183927-y](https://github.com/user-attachments/assets/c073cd54-9405-4317-a65f-a221275df641)
![telegram-cloud-photo-size-1-5073602166656183928-y](https://github.com/user-attachments/assets/abe3e80f-7dab-4fc4-b5b2-a9004ceeea4d)
![telegram-cloud-photo-size-1-5073602166656183929-y](https://github.com/user-attachments/assets/4df08d5c-ff12-424f-8bc7-2716935fd73a)
![telegram-cloud-photo-size-1-5073602166656183931-y](https://github.com/user-attachments/assets/97990a57-7ed8-46e3-8efd-90ebdd0c5ad2)
![telegram-cloud-photo-size-1-5073602166656183932-y](https://github.com/user-attachments/assets/b0989a5c-5c12-4a21-ad8d-27c727013b3c)

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
- **Nix** - Required for dependency management (enforced at build time)

## Quick Start

### 1. Install Nix

The project requires Nix for managing dependencies like Ghostty terminal emulator.

**macOS/Linux:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**Platform-specific notes:**

**macOS:**
- You may need to create the /nix directory first:
  ```bash
  sudo mkdir /nix && sudo chown $USER /nix
  ```
- On Apple Silicon, Rosetta 2 may be needed:
  ```bash
  softwareupdate --install-rosetta
  ```

**Linux:**
- SELinux users may need additional configuration
- Ubuntu/Debian users should use the --daemon flag

### 2. Enable Flakes

After installation, enable flakes by adding to `~/.config/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

### 3. Clone and Enter Development Environment

```bash
git clone <repository-url>
cd plue
nix develop
```

### 3. Build and Run

```bash
# Build the project
zig build swift

# Run the app
zig build run

# Or run the Swift executable directly
.build/release/plue
```

### 4. Install Command Line Interface (Optional)

Install the `plue` command globally for VSCode-like CLI usage:

```bash
# Install the CLI command globally
./scripts/install.sh

# Now you can use plue from anywhere
plue                       # Open in current directory  
plue ~/my-project         # Open in specific directory
plue .                    # Open in current directory (explicit)
```

Example CLI usage:
```bash
cd ~/code/my-awesome-project
plue                      # Opens Plue in this directory

# Or open directly in any project
plue ~/code/another-project
```

## Development

The build system enforces Nix usage to ensure all dependencies are available:

```bash
# Build the complete project (Zig libraries + Swift application)
zig build

# Build and run the application
zig build run
```

**Note:** If you try to build outside of Nix, you'll see an error with installation instructions.

To bypass the Nix check (not recommended - some features won't work):
```bash
zig build -Dskip-nix-check=true
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
