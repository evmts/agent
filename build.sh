#!/bin/bash

# Build the Zig library first
echo "Building Zig library..."
zig build

# Then build the Swift project
echo "Building Swift project..."
swift build -Xlinker -L$(pwd)/zig-out/lib