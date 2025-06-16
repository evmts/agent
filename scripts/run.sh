#!/usr/bin/env bash
# Build and run script for Plue
# Uses two-stage build: Zig in Nix, Swift outside Nix

set -e

# Stage 1: Build Zig libraries in Nix
echo "Building Zig libraries in Nix..."
nix develop -c zig build

# Stage 2: Build Swift app outside Nix (if needed)
if [ ! -f ".build/release/plue" ] || [ "zig-out/lib/libplue.a" -nt ".build/release/plue" ]; then
    echo "Building Swift app..."
    swift build -c release -Xlinker -Lzig-out/lib
fi

# Run the app
echo "Starting Plue..."
.build/release/plue "$@"