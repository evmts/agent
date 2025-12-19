#!/bin/bash

# Build setup script for Plue
# This script helps set up the environment and resolve common build issues

echo "Setting up Plue build environment..."

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    
    # Try different package managers
    if command -v bun &> /dev/null; then
        echo "Using bun..."
        bun install
    elif command -v npm &> /dev/null; then
        echo "Using npm..."
        npm install
    elif command -v yarn &> /dev/null; then
        echo "Using yarn..."
        yarn install
    else
        echo "No package manager found. Please install Node.js and npm."
        exit 1
    fi
fi

# Generate Astro types
echo "Generating Astro types..."
if command -v bun &> /dev/null; then
    bun run astro sync
elif command -v npm &> /dev/null; then
    npm run postinstall
fi

echo "Build setup complete!"
echo ""
echo "Available commands:"
echo "  npm run dev       - Start development server"
echo "  npm run build     - Build for production"
echo "  npm run check     - Run Astro check"
echo "  npm run lint      - Run linter"
echo "  npm run type-check - Run TypeScript check"