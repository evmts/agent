# Ghostty Nix Integration Guide

## Overview

This document explains how to integrate Ghostty using Nix, which handles all the complex dependencies automatically.

## What We've Set Up

1. **Updated `flake.nix`** to:
   - Add Ghostty as a flake input
   - Include Ghostty package in build inputs
   - Export Ghostty library paths during build and development

2. **Updated `build.zig`** to:
   - Accept Ghostty library and include paths as build options
   - Link with the Ghostty library when paths are provided

## How to Use

### Prerequisites
- Install Nix with flakes enabled
- macOS or Linux (Darwin or Linux in Nix terms)

### Building with Nix

1. **Enter the Nix development shell**:
   ```bash
   nix develop
   ```
   This will:
   - Download and build Ghostty with all its dependencies
   - Set up environment variables `GHOSTTY_LIB_PATH` and `GHOSTTY_INCLUDE_PATH`
   - Make the Ghostty library available for linking

2. **Build the project**:
   ```bash
   zig build
   ```
   The build system will automatically detect and use the Ghostty library from Nix.

3. **Or build everything with Nix**:
   ```bash
   nix build
   ```

## How It Works

### Dependency Resolution
Nix handles all of Ghostty's complex dependencies:
- `objc` (Objective-C bindings)
- `cimgui` (Dear ImGui C bindings)
- `ziglyph` (Unicode handling)
- `macos` (macOS-specific functionality)
- GTK4, GLib, fontconfig, freetype, harfbuzz, etc.

### Library Linking
When building inside the Nix environment:
1. Ghostty is built as a proper library with all dependencies
2. The library path is exposed via `GHOSTTY_LIB_PATH`
3. Our build.zig uses these paths to link against libghostty

### Integration Points
The actual Ghostty C functions become available:
- `ghostty_init()`
- `ghostty_app_new()`
- `ghostty_surface_new()`
- And all other functions from Ghostty's embedded API

## Next Steps

Once you have Nix installed:

1. Run `nix flake update` to fetch Ghostty
2. Enter `nix develop` to set up the environment
3. Update `src/ghostty_terminal.zig` to remove the stub implementations
4. Build and test the integration

## Benefits of Nix Approach

1. **Reproducible builds** - Same dependencies everywhere
2. **No manual dependency management** - Nix handles everything
3. **Isolated environment** - Won't conflict with system packages
4. **Easy updates** - Just update the flake input

## Troubleshooting

If Ghostty's flake doesn't build libghostty by default, you may need to:
1. Override the Ghostty package to build with `app_runtime = .none`
2. Or use Ghostty's libghostty output if they provide one

Example override in flake.nix:
```nix
ghosttyPkg = ghostty.packages.${system}.default.override {
  app_runtime = "none";  # Build as library, not app
};
```