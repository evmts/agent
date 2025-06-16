#!/bin/bash

# Script to copy all Zig and Swift source files to clipboard in markdown format
# Usage: ./scripts/copy-code-to-clipboard.sh

# Create a temporary file
TEMP_FILE=$(mktemp)

# Function to add file content in markdown code block
add_file_to_markdown() {
    local file="$1"
    local lang="$2"
    
    echo "" >> "$TEMP_FILE"
    echo "## $file" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "\`\`\`$lang" >> "$TEMP_FILE"
    cat "$file" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "\`\`\`" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
}

# Header
echo "# Plue Source Code" > "$TEMP_FILE"
echo "" >> "$TEMP_FILE"
echo "Generated on: $(date)" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

# Add table of contents
echo "## Table of Contents" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"
echo "### Zig Files" >> "$TEMP_FILE"
find . -name "*.zig" -type f | grep -v ".zig-cache" | grep -v "zig-out" | sort | while read -r file; do
    echo "- [$file](#$(echo "$file" | sed 's/[^a-zA-Z0-9]/-/g'))" >> "$TEMP_FILE"
done

echo "" >> "$TEMP_FILE"
echo "### Swift Files" >> "$TEMP_FILE"
find . -name "*.swift" -type f | grep -v ".build" | grep -v "DerivedData" | sort | while read -r file; do
    echo "- [$file](#$(echo "$file" | sed 's/[^a-zA-Z0-9]/-/g'))" >> "$TEMP_FILE"
done

echo "" >> "$TEMP_FILE"
echo "---" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

# Process Zig files
echo "# Zig Source Files" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

find . -name "*.zig" -type f | grep -v ".zig-cache" | grep -v "zig-out" | sort | while read -r file; do
    echo "Processing: $file"
    add_file_to_markdown "$file" "zig"
done

# Process Swift files  
echo "# Swift Source Files" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

find . -name "*.swift" -type f | grep -v ".build" | grep -v "DerivedData" | sort | while read -r file; do
    echo "Processing: $file"
    add_file_to_markdown "$file" "swift"
done

# Copy to clipboard based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    cat "$TEMP_FILE" | pbcopy
    echo ""
    echo "✅ All Zig and Swift files have been copied to clipboard in markdown format!"
    echo "📊 Stats:"
    echo "   - Zig files: $(find . -name "*.zig" -type f | grep -v ".zig-cache" | grep -v "zig-out" | wc -l | tr -d ' ')"
    echo "   - Swift files: $(find . -name "*.swift" -type f | grep -v ".build" | grep -v "DerivedData" | wc -l | tr -d ' ')"
    echo "   - Total size: $(cat "$TEMP_FILE" | wc -c | awk '{print int($1/1024) " KB"}')"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command -v xclip &> /dev/null; then
        cat "$TEMP_FILE" | xclip -selection clipboard
        echo "✅ Copied to clipboard using xclip!"
    elif command -v xsel &> /dev/null; then
        cat "$TEMP_FILE" | xsel --clipboard --input
        echo "✅ Copied to clipboard using xsel!"
    else
        echo "❌ No clipboard utility found. Install xclip or xsel."
        echo "💾 Output saved to: $TEMP_FILE"
        exit 1
    fi
else
    echo "❌ Unsupported OS. Output saved to: $TEMP_FILE"
    exit 1
fi

# Clean up
rm -f "$TEMP_FILE"