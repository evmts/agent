#!/bin/bash
set -e

echo "Building jj-ffi Rust library..."
cargo build --release

echo ""
echo "Building Zig example..."
zig build-exe example.zig \
    -I. \
    -L./target/release \
    -ljj_ffi \
    -lc \
    -framework Security \
    -framework CoreFoundation \
    -lresolv

echo ""
echo "Example built successfully: ./example"
echo ""
echo "Usage: ./example <path-to-jj-workspace>"
