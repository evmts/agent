#!/usr/bin/env bash
# Two-stage build script for macOS (similar to Ghostty's approach)
# Stage 1: Build Zig components in Nix for reproducibility
# Stage 2: Build Swift components outside Nix (SPM not available in Nix)

set -e

echo "=== Plue macOS Build ==="
echo "Stage 1/2: Building Zig libraries in Nix environment..."
nix develop -c zig build

echo "Stage 2/2: Building Swift app with SPM (outside Nix)..."
# Must use system Swift as Nix's Swift lacks Swift Package Manager
swift build --configuration release -Xlinker -Lzig-out/lib

echo ""
echo "✅ Build complete!"
echo "Run with: .build/release/plue"
echo ""
echo "Note: This two-stage process ensures reproducible Zig builds while"
echo "      working around Nix's lack of Swift Package Manager support."