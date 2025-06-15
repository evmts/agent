#!/bin/bash
# Build script for testing Ghostty integration with Nix

echo "Building Plue with Ghostty integration using Nix..."
echo ""

# Check if nix is installed
if ! command -v nix &> /dev/null; then
    echo "Error: Nix is not installed!"
    echo "Please install Nix first: https://nixos.org/download.html"
    echo ""
    echo "Quick install (macOS/Linux):"
    echo "  sh <(curl -L https://nixos.org/nix/install)"
    exit 1
fi

# Check if flakes are enabled
if ! nix flake --help &> /dev/null; then
    echo "Error: Nix flakes are not enabled!"
    echo "Please enable flakes by adding to ~/.config/nix/nix.conf:"
    echo "  experimental-features = nix-command flakes"
    exit 1
fi

echo "Updating flake to fetch Ghostty..."
nix flake update

echo ""
echo "Building with Nix..."
nix build

if [ $? -eq 0 ]; then
    echo ""
    echo "Build successful! The binary is available at: ./result/bin/plue"
    echo ""
    echo "You can also enter the development shell with:"
    echo "  nix develop"
    echo ""
    echo "Then build with Zig directly:"
    echo "  zig build"
else
    echo ""
    echo "Build failed. Please check the error messages above."
fi