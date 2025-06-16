#!/bin/bash

# Simple build script for Plue library
echo "Building Plue library..."

# Create lib directory if it doesn't exist
mkdir -p lib

# Build the library with minimal dependencies
zig build-lib src/libplue.zig \
  -dynamic \
  -femit-bin=lib/libplue.dylib \
  -lc \
  -I include \
  --mod app:app:src/app.zig \
  --mod terminal:terminal:src/terminal.zig \
  --mod ghostty_terminal:ghostty_terminal:src/ghostty_terminal.zig \
  || echo "Build failed. This is expected without proper module setup."

echo "Note: Full build requires 'zig build' with proper module configuration"