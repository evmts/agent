#!/bin/bash

echo "Testing Ghostty Terminal Integration"
echo "===================================="
echo ""

# Run the application
echo "Running plue with Ghostty terminal tab..."
.build/release/plue &
APP_PID=$!

echo "Application started with PID: $APP_PID"
echo ""
echo "To test the terminal:"
echo "1. Click on the Terminal tab"
echo "2. The terminal should initialize (check console for messages)"
echo "3. Type some text in the input field and press Send"
echo ""
echo "Press Ctrl+C to stop the application"

# Wait for user to stop
wait $APP_PID