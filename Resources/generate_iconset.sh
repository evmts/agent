#!/bin/bash

# Create iconset directory
mkdir -p Plue.iconset

# Generate all required icon sizes from SVG
# Note: This requires librsvg (can be installed with: brew install librsvg)

echo "Generating app icons..."

# Generate PNG files at different sizes
rsvg-convert -w 16 -h 16 PlueIcon.svg -o Plue.iconset/icon_16x16.png
rsvg-convert -w 32 -h 32 PlueIcon.svg -o Plue.iconset/icon_16x16@2x.png
rsvg-convert -w 32 -h 32 PlueIcon.svg -o Plue.iconset/icon_32x32.png
rsvg-convert -w 64 -h 64 PlueIcon.svg -o Plue.iconset/icon_32x32@2x.png
rsvg-convert -w 128 -h 128 PlueIcon.svg -o Plue.iconset/icon_128x128.png
rsvg-convert -w 256 -h 256 PlueIcon.svg -o Plue.iconset/icon_128x128@2x.png
rsvg-convert -w 256 -h 256 PlueIcon.svg -o Plue.iconset/icon_256x256.png
rsvg-convert -w 512 -h 512 PlueIcon.svg -o Plue.iconset/icon_256x256@2x.png
rsvg-convert -w 512 -h 512 PlueIcon.svg -o Plue.iconset/icon_512x512.png
rsvg-convert -w 1024 -h 1024 PlueIcon.svg -o Plue.iconset/icon_512x512@2x.png

# Create the .icns file
iconutil -c icns Plue.iconset -o Plue.icns

echo "Icon generation complete! Created Plue.icns"

# Clean up
rm -rf Plue.iconset