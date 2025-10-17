#!/bin/bash

# Individual tool testing script
# Usage: ./test-individual.sh <tool_name>

if [ -z "$1" ]; then
    echo "Usage: ./test-individual.sh <tool_name>"
    echo ""
    echo "Available tools:"
    echo "  read       - Test Read tool"
    echo "  write      - Test Write tool"
    echo "  edit       - Test Edit tool"
    echo "  glob       - Test Glob tool"
    echo "  grep       - Test Grep tool"
    echo "  ls         - Test List tool"
    echo "  bash       - Test Bash tool"
    echo "  multiedit  - Test MultiEdit tool"
    echo "  patch      - Test Patch tool"
    echo "  webfetch   - Test WebFetch tool"
    echo "  todo       - Test Todo tools"
    echo "  all        - Run all tests"
    exit 1
fi

# Build agent if not exists or source is newer
if [ ! -f ./agent ] || [ main.go -nt ./agent ]; then
    echo "Building agent..."
    go build -o agent .
    if [ $? -ne 0 ]; then
        echo "❌ Build failed"
        exit 1
    fi
fi

# Create test area
mkdir -p test_area
cd test_area

# Setup test files if needed
if [ ! -f test.txt ]; then
    echo "Original line 1" > test.txt
    echo "Original line 2" >> test.txt
    echo "Original line 3" >> test.txt
fi

if [ ! -f sample.js ]; then
    echo "function test() {" > sample.js
    echo "  console.log('hello');" >> sample.js
    echo "}" >> sample.js
fi

mkdir -p subdir
if [ ! -f subdir/nested.txt ]; then
    echo "nested content" > subdir/nested.txt
fi

cd ..

TOOL="$1"

case "$TOOL" in
    read)
        echo "📖 Testing Read Tool"
        ./agent -p "Use the read tool to read the file test_area/test.txt"
        ;;

    write)
        echo "📝 Testing Write Tool"
        ./agent -p "Use the write tool to create a new file test_area/output.txt with content 'Test output'"
        ;;

    edit)
        echo "✏️  Testing Edit Tool"
        ./agent -p "Use the edit tool to change 'Original line 2' to 'Modified line 2' in test_area/test.txt"
        ;;

    glob)
        echo "🔍 Testing Glob Tool"
        ./agent -p "Use the glob tool to find all .txt files in test_area"
        ;;

    grep)
        echo "🔎 Testing Grep Tool"
        ./agent -p "Use the grep tool to search for 'line' in test_area/*.txt files"
        ;;

    ls)
        echo "📁 Testing List Tool"
        ./agent -p "Use the list tool to show the directory tree of test_area"
        ;;

    bash)
        echo "💻 Testing Bash Tool"
        ./agent -p "Use the bash tool to run 'ls -lh test_area'"
        ;;

    multiedit)
        echo "📝✏️  Testing MultiEdit Tool"
        ./agent -p "Use the multiedit tool to make two changes to test_area/test.txt: change 'Original line 1' to 'First Line' and 'Original line 3' to 'Third Line'"
        ;;

    patch)
        echo "🔧 Testing Patch Tool"
        ./agent -p "Use the patch tool to apply this patch:
*** Begin Patch
*** Update File: test_area/test.txt
@@ context @@
-Original line 2
+Patched line 2
*** End Patch"
        ;;

    webfetch)
        echo "🌐 Testing WebFetch Tool"
        ./agent -p "Use the webfetch tool to fetch https://example.com"
        ;;

    todo)
        echo "📋 Testing Todo Tools"
        ./agent -p "Use the todowrite tool to create a todo list with these items: 'Test task 1' (status: pending, activeForm: 'Testing task 1'), 'Test task 2' (status: in_progress, activeForm: 'Testing task 2')"
        ;;

    all)
        echo "Running all tests..."
        for tool in read write edit glob grep ls bash multiedit webfetch todo; do
            echo ""
            echo "========================================"
            $0 $tool
            echo "========================================"
            echo ""
            sleep 1
        done
        ;;

    *)
        echo "Unknown tool: $TOOL"
        exit 1
        ;;
esac
