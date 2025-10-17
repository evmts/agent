#!/bin/bash

# Test script for all agent tools
# Usage: ./test-tools.sh

echo "==================================="
echo "Agent Tools Test Suite"
echo "==================================="
echo ""

# Build the agent first
echo "Building agent..."
go build -o agent-test main.go api.go
if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi
echo "✅ Build successful"
echo ""

# Create test directory and files
mkdir -p test_area
cd test_area

# Create test files
echo "Line 1" > test.txt
echo "Line 2" >> test.txt
echo "Line 3" >> test.txt

echo "function test() {" > test.js
echo "  console.log('hello');" >> test.js
echo "}" >> test.js

mkdir -p subdir
echo "nested file" > subdir/nested.txt

cd ..

echo "==================================="
echo "Testing Tools"
echo "==================================="
echo ""

# Test 1: Read Tool
echo "📖 Test 1: Read Tool"
./agent-test -p "Read the file test_area/test.txt and show me its contents"
echo ""

# Test 2: Write Tool
echo "📝 Test 2: Write Tool"
./agent-test -p "Create a new file test_area/new.txt with the content 'Hello World'"
echo ""

# Test 3: Edit Tool
echo "✏️  Test 3: Edit Tool"
./agent-test -p "Edit test_area/test.txt and replace 'Line 2' with 'Modified Line 2'"
echo ""

# Test 4: Glob Tool
echo "🔍 Test 4: Glob Tool"
./agent-test -p "Find all .txt files in test_area directory"
echo ""

# Test 5: Grep Tool
echo "🔎 Test 5: Grep Tool"
./agent-test -p "Search for the word 'Line' in test_area directory"
echo ""

# Test 6: List Tool
echo "📁 Test 6: List Tool"
./agent-test -p "Show me the directory structure of test_area"
echo ""

# Test 7: Bash Tool
echo "💻 Test 7: Bash Tool"
./agent-test -p "Run 'ls -la test_area' to show directory contents"
echo ""

# Test 8: MultiEdit Tool
echo "📝✏️  Test 8: MultiEdit Tool"
./agent-test -p "Make two edits to test_area/test.txt: change 'Line 1' to 'First Line' and 'Line 3' to 'Third Line'"
echo ""

# Test 9: WebFetch Tool
echo "🌐 Test 9: WebFetch Tool"
./agent-test -p "Fetch the content from https://example.com and convert to markdown"
echo ""

# Test 10: Todo Tools
echo "📋 Test 10: Todo Write Tool"
./agent-test -p "Create a todo list with two items: 'Task 1' (pending) and 'Task 2' (in_progress)"
echo ""

echo "==================================="
echo "Test Suite Complete"
echo "==================================="
echo ""
echo "Cleanup test files? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    rm -rf test_area
    rm -f agent-test
    echo "✅ Cleaned up test files"
fi
