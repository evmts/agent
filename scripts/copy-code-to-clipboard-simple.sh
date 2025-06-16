#!/bin/bash

# Simple script to copy all Zig and Swift source files to clipboard in markdown format
# Usage: ./scripts/copy-code-to-clipboard-simple.sh

# Create a temporary file
TEMP_FILE=$(mktemp)

# Header
echo "# Plue Source Code" > "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

# Process Zig files
find . -name "*.zig" -type f | grep -v ".zig-cache" | grep -v "zig-out" | sort | while read -r file; do
    echo "Processing: $file"
    echo "## $file" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "\`\`\`zig" >> "$TEMP_FILE"
    cat "$file" >> "$TEMP_FILE"
    echo "\`\`\`" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
done

# Process Swift files  
find . -name "*.swift" -type f | grep -v ".build" | grep -v "DerivedData" | sort | while read -r file; do
    echo "Processing: $file"
    echo "## $file" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "\`\`\`swift" >> "$TEMP_FILE"
    cat "$file" >> "$TEMP_FILE"
    echo "\`\`\`" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
done

# Copy to clipboard
if [[ "$OSTYPE" == "darwin"* ]]; then
    cat "$TEMP_FILE" | pbcopy
    echo "✅ Copied to clipboard!"
    echo "📊 Total size: $(cat "$TEMP_FILE" | wc -c | awk '{print int($1/1024) " KB"}')"
else
    echo "❌ This script currently only supports macOS. Output saved to: $TEMP_FILE"
fi

# Clean up
rm -f "$TEMP_FILE"