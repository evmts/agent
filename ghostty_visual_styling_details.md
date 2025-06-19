# Ghostty Visual Styling Details

Based on my analysis of the Ghostty codebase, here are the exact visual styling parameters:

## Color Schemes

### Default Color Palette
- **Background**: `#282C34` (RGB: 40, 44, 52)
- **Foreground**: `#FFFFFF` (RGB: 255, 255, 255)

### Default 16-Color Palette
```
Black:          #1D1F21 (RGB: 29, 31, 33)
Red:            #CC6666 (RGB: 204, 102, 102)
Green:          #B5BD68 (RGB: 181, 189, 104)
Yellow:         #F0C674 (RGB: 240, 198, 116)
Blue:           #81A2BE (RGB: 129, 162, 190)
Magenta:        #B294BB (RGB: 178, 148, 187)
Cyan:           #8ABEB7 (RGB: 138, 190, 183)
White:          #C5C8C6 (RGB: 197, 200, 198)

Bright Black:   #666666 (RGB: 102, 102, 102)
Bright Red:     #D54E53 (RGB: 213, 78, 83)
Bright Green:   #B9CA4A (RGB: 185, 202, 74)
Bright Yellow:  #E7C547 (RGB: 231, 197, 71)
Bright Blue:    #7AA6DA (RGB: 122, 166, 218)
Bright Magenta: #C397D8 (RGB: 195, 151, 216)
Bright Cyan:    #70C0B1 (RGB: 112, 192, 177)
Bright White:   #EAEAEA (RGB: 234, 234, 234)
```

## Font Configuration

### Default Font Sizes
- **macOS**: 13pt
- **Other platforms**: 12pt

### Font Metrics (calculated defaults)
- Cell dimensions are calculated based on font metrics
- Cell height = ascent - descent + line_gap
- Cell width = measured from ASCII range
- Default underline thickness = 15% of ex-height (min 1px)
- Text is centered vertically in cells with half line gap above and below

## Window Styling

### Padding
- **Default window padding**: 2 points on all sides
  - `window-padding-x`: 2pt (left and right)
  - `window-padding-y`: 2pt (top and bottom)
- **Padding balance**: false (top-left alignment by default)
- **Padding color**: matches background color by default

### Window Properties
- **Window decorations**: "auto" (platform-specific)
- **Window shadow**: true (on macOS)
- **Background opacity**: 1.0 (fully opaque)
- **Background blur**: false (0 intensity)
- **Unfocused split opacity**: 0.7
- **Split divider color**: auto-calculated based on background

### macOS-Specific Styling
- **Titlebar style**: "transparent" (default)
  - Other options: "native", "tabs", "hidden"
- **Window buttons**: visible
- **Titlebar proxy icon**: visible
- **VSync**: true (synchronized with display refresh rate)
- **Window theme**: "auto" (follows system theme)

### Visual Effects
- **Alpha blending color space**: "native" (Display P3 on macOS, sRGB on Linux)
- **Cursor style**: block (default)
- **Cursor opacity**: 1.0
- **Cursor blink**: enabled by default
- **Minimum contrast ratio**: 1.0

### Animation and Timing
- **Resize overlay duration**: 750ms
- **Quick terminal animation duration**: 200ms (macOS)
- **Undo timeout**: 5 seconds

### Cell Adjustments (all nullable/optional)
- `adjust-cell-width`
- `adjust-cell-height`
- `adjust-font-baseline`
- `adjust-underline-position`
- `adjust-underline-thickness`
- `adjust-strikethrough-position`
- `adjust-strikethrough-thickness`
- `adjust-overline-position`
- `adjust-overline-thickness`
- `adjust-cursor-thickness`
- `adjust-cursor-height`
- `adjust-box-thickness`

## Terminal Appearance Features

### Selection
- **Selection colors**: inverted by default (no specific colors set)
- **Selection clear on typing**: true
- **Copy on select**: true (Linux and macOS)

### Mouse Behavior
- **Hide while typing**: false
- **Scroll multiplier**: 3.0 (3 lines per tick)
- **Focus follows mouse**: false

### Other Visual Settings
- **Resize overlay**: "after-first" (shows after initial creation)
- **Resize overlay position**: "center"
- **Image storage limit**: 320MB per screen
- **Grapheme width method**: "unicode"

## Platform-Specific Notes

### macOS
- Uses CoreText for font rendering
- Supports native fullscreen mode
- Has transparent titlebar option for seamless integration
- Window shadow enabled by default
- Display P3 color space for alpha blending

### Linux
- Uses FreeType for font rendering
- Default FreeType flags: hinting, force-autohint, monochrome, autohint
- GTK titlebar enabled by default
- sRGB color space for alpha blending

## Design Philosophy
Ghostty emphasizes:
1. Clean, minimal interface with transparent titlebar on macOS
2. Precise font metrics calculation for consistent text rendering
3. Flexible configuration with sensible defaults
4. Platform-native appearance and behavior
5. Performance-optimized rendering with proper VSync

These parameters can be used to replicate Ghostty's visual appearance in your terminal implementation.