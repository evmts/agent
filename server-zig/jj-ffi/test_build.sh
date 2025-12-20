#!/bin/bash
set -e

echo "=========================================="
echo "Testing jj-ffi Build Process"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v cargo &> /dev/null; then
    echo "❌ cargo not found. Please install Rust."
    exit 1
fi

if ! command -v zig &> /dev/null; then
    echo "❌ zig not found. Please install Zig."
    exit 1
fi

echo "✓ cargo found: $(cargo --version)"
echo "✓ zig found: $(zig version)"
echo ""

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf target/ *.o example zig-cache/ zig-out/
echo "✓ Cleaned"
echo ""

# Build Rust library
echo "Building jj-ffi Rust library..."
cargo build --release
if [ $? -eq 0 ]; then
    echo "✓ Rust library built successfully"
else
    echo "❌ Rust library build failed"
    exit 1
fi
echo ""

# Check library exists
echo "Checking library output..."
if [ -f "target/release/libjj_ffi.a" ]; then
    echo "✓ Static library: target/release/libjj_ffi.a"
    ls -lh target/release/libjj_ffi.a
else
    echo "❌ Static library not found"
    exit 1
fi

if [ -f "target/release/libjj_ffi.dylib" ]; then
    echo "✓ Dynamic library: target/release/libjj_ffi.dylib"
    ls -lh target/release/libjj_ffi.dylib
elif [ -f "target/release/libjj_ffi.so" ]; then
    echo "✓ Dynamic library: target/release/libjj_ffi.so"
    ls -lh target/release/libjj_ffi.so
fi
echo ""

# Check header exists
echo "Checking header file..."
if [ -f "jj_ffi.h" ]; then
    echo "✓ Header file exists: jj_ffi.h"
    echo "  Functions exported: $(grep -c "^[a-zA-Z].*(" jj_ffi.h || true)"
else
    echo "❌ Header file not found"
    exit 1
fi
echo ""

# Test library symbols
echo "Checking exported symbols..."
if command -v nm &> /dev/null; then
    SYMBOL_COUNT=$(nm target/release/libjj_ffi.a | grep -c " T _jj_" || true)
    echo "✓ Exported jj_* functions: $SYMBOL_COUNT"
    echo "  Sample functions:"
    nm target/release/libjj_ffi.a | grep " T _jj_" | head -5 | sed 's/^/    /'
else
    echo "⚠ nm not available, skipping symbol check"
fi
echo ""

# Build Zig example (if we're on macOS)
if [ -f "example.zig" ]; then
    echo "Building Zig example..."
    if [ "$(uname)" = "Darwin" ]; then
        zig build-exe example.zig \
            -I. \
            -L./target/release \
            -ljj_ffi \
            -lc \
            -framework Security \
            -framework CoreFoundation \
            -lresolv
        if [ $? -eq 0 ]; then
            echo "✓ Zig example built successfully"
            echo "  Binary: ./example"
            ls -lh ./example
        else
            echo "❌ Zig example build failed"
            exit 1
        fi
    else
        echo "⚠ Non-macOS platform, skipping Zig example build"
        echo "  (Adjust linker flags for your platform)"
    fi
fi
echo ""

# Summary
echo "=========================================="
echo "✓ Build Test Completed Successfully"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Test with: ./example /path/to/jj/workspace"
echo "  2. Integrate into build.zig"
echo "  3. Run: zig build"
echo ""
