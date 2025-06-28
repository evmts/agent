# Plue (under development)

**A multi-agent coding assistant built with Swift and Zig**

Plue is a native macOS application that provides an intelligent coding assistant interface with multiple interaction modes. It combines a modern Swift UI with high-performance Zig backend libraries to deliver a responsive and powerful development tool.

**Note:** This project currently only builds on macOS due to its native macOS UI components and frameworks.

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
  - Business logic and state management
  - Farcaster protocol implementation
  - Core processing logic
- **Unified Build System** - Zig build system orchestrates both Zig and Swift compilation

### Build System

Plue uses the **Zig build system** as the primary build orchestrator, which wraps and manages both:
- Zig library compilation
- Swift Package Manager (SPM) for the Swift application

The build process:
1. **Stage 1**: Build Zig libraries
2. **Stage 2**: Build Swift application using SPM, linking against Zig libraries

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Zig 0.14.1** (or later)
- **Swift 5.8+** (included with Xcode)

## Quick Start

### 1. Install Zig

Download and install Zig from [https://ziglang.org/download/](https://ziglang.org/download/)

**macOS (using Homebrew):**
```bash
brew install zig
```

### 2. Clone the Repository

```bash
git clone <repository-url>
cd plue
```

### 3. Build and Run

```bash
# Build the complete project
zig build

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

### Build Commands

```bash
# Build the complete project (Zig libraries + Swift application)
zig build

# Build and run the application
zig build run

# Run tests
zig build test
```

### Build Commands

| Command | Description |
|---------|-------------|
| `zig build` | Build complete project (Zig + Swift) |
| `zig build run` | Build and run the application |
| `zig build test` | Run unit tests |

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
└── .github/workflows/    # CI/CD configuration
```

## Development Environment

Required tools:

- **Xcode** - For Swift compiler and macOS SDKs
- **Zig** - Zig compiler and build system (0.14.1 or later)
- **macOS Frameworks** - Foundation, AppKit, WebKit, Security (included with Xcode)

## Building

### Local Development

```bash
# Build complete project
zig build

# Run the application
zig build run

# Run tests
zig build test
```

### Manual Build Steps (if needed)

If you need to build components separately:

```bash
# Build Zig libraries only
zig build-lib -dynamic -OReleaseFast src/libplue.zig -femit-bin=zig-out/lib/libplue.dylib

# Build Swift application
swift build --configuration release -Xlinker -Lzig-out/lib
```

## Contributing

1. **Clone the repository** and ensure you have Zig and Xcode installed
2. **Make your changes** to Swift or Zig code
3. **Test your changes**: `zig build test`
4. **Build and verify**: `zig build run`
5. **Submit a pull request**

## CI/CD

The project uses GitHub Actions for:

- **Automated builds** on every push and PR
- **Test execution** to ensure code quality
- **Dependency updates** via Dependabot

## License

[Add your license here]

## Support

[Add support information here]
