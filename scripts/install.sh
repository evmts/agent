#!/bin/bash

# Plue CLI Installation Script
# This script installs the 'plue' command globally so you can use it from anywhere

set -e

echo "🚀 Installing Plue CLI..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Build the project first
echo "📦 Building Plue..."
cd "$PROJECT_ROOT"

# Build with Zig
if ! zig build swift; then
    echo "❌ Build failed. Please check the error messages above."
    exit 1
fi

echo "✅ Build completed successfully"

# Check if the executable exists
PLUE_EXECUTABLE="$PROJECT_ROOT/.build/release/plue"
if [ ! -f "$PLUE_EXECUTABLE" ]; then
    echo "❌ Plue executable not found at $PLUE_EXECUTABLE"
    echo "   Please check the build output for errors."
    exit 1
fi

# Create /usr/local/bin if it doesn't exist
if [ ! -d "/usr/local/bin" ]; then
    echo "📁 Creating /usr/local/bin directory..."
    sudo mkdir -p /usr/local/bin
fi

# Copy the CLI script to /usr/local/bin
echo "📋 Installing plue command to /usr/local/bin..."
sudo cp "$SCRIPT_DIR/plue" /usr/local/bin/plue
sudo chmod +x /usr/local/bin/plue

# Update the script to point to the correct executable location
sudo sed -i.bak "s|PLUE_APP=\".*\.build/release/plue\"|PLUE_APP=\"$PLUE_EXECUTABLE\"|" /usr/local/bin/plue
sudo rm /usr/local/bin/plue.bak

echo "✅ Plue CLI installed successfully!"
echo ""
echo "🎉 You can now use 'plue' from anywhere:"
echo "   plue                    # Open Plue in current directory"
echo "   plue /path/to/project   # Open Plue in specific directory"
echo "   plue .                  # Open Plue in current directory"
echo "   plue ~/Documents        # Open Plue in Documents folder"
echo ""
echo "💡 Example usage:"
echo "   cd ~/my-project && plue    # Opens Plue in my-project directory"
echo "   plue ~/code/awesome-app    # Opens Plue in awesome-app directory"