#!/bin/bash

# Output file
OUTPUT="code_output.md"

# Clear/create output file
> "$OUTPUT"

# Copy all Zig files
echo "# Zig Code" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Find all .zig files and process them
find . -path "./zig-cache" -prune -o -path "./zig-out" -prune -o -type f -name "*.zig" -print | while read -r file; do
    # Skip zig-cache and zig-out directories
    if [[ "$file" == *"zig-cache"* ]] || [[ "$file" == *"zig-out"* ]]; then
        continue
    fi
    
    # Only include files matching our patterns
    if [[ "$file" == "./build.zig" ]] || [[ "$file" == ./src/**/*.zig ]] || [[ "$file" == ./test/**/*.zig ]]; then
        echo '```zig' >> "$OUTPUT"
        echo "// File: $file" >> "$OUTPUT"
        cat "$file" >> "$OUTPUT"
        echo '```' >> "$OUTPUT"
        echo "" >> "$OUTPUT"
    fi
done

# Copy all Swift files
echo "# Swift Code" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Find all Swift files in Sources/plue/
find Sources/plue -name "*.swift" -type f | while read -r file; do
    echo '```swift' >> "$OUTPUT"
    echo "// File: $file" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
done

echo "Code has been copied to $OUTPUT"