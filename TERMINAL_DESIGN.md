# Plue Terminal Design Document
## Ghostty-Inspired Single-Pane Terminal Implementation

### Executive Summary

This document outlines the design for implementing a Ghostty-inspired terminal in Plue. Our goal is to create a near-identical copy of Ghostty's architecture and visual appearance, but simplified to support only a single terminal pane (no splits, tabs, or advanced features). We will leverage the existing Ghostty backend (libghostty) while creating a streamlined Swift frontend.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Swift UI Layer                           │
├─────────────────────────────────────────────────────────────┤
│  PlueTerminalView (SwiftUI)                                 │
│  ├─ PlueTerminalSurface (NSViewRepresentable)              │
│  │  └─ PlueTerminalSurfaceView (NSView + Metal)            │
│  └─ Overlays (Resize, Error states)                        │
├─────────────────────────────────────────────────────────────┤
│                    C FFI Bridge                              │
├─────────────────────────────────────────────────────────────┤
│                 Zig Backend (libghostty)                     │
│  ├─ Terminal State Management                               │
│  ├─ Text Processing & Parsing                               │
│  └─ Rendering Commands Generation                           │
└─────────────────────────────────────────────────────────────┘
```

### Component Specifications

#### 1. PlueTerminalSurfaceView (Core Terminal NSView)

**Purpose**: Direct port of Ghostty's SurfaceView, handling Metal rendering and input.

**Key Responsibilities**:
- Metal layer management and rendering
- Keyboard and mouse input handling via NSTextInputClient
- Display link synchronization for smooth rendering
- Coordinate system management (pixel ↔ cell conversions)
- Communication with Zig backend via FFI

**Implementation Details**:
```swift
class PlueTerminalSurfaceView: NSView, NSTextInputClient, CALayerDelegate {
    // Metal rendering
    private var metalLayer: CAMetalLayer
    private var displayLink: CVDisplayLink
    private var renderer: PlueMetalRenderer
    
    // Terminal state
    private var surface: OpaquePointer  // Ghostty surface handle
    private var needsRender: Bool = false
    
    // Font metrics
    private var cellWidth: CGFloat
    private var cellHeight: CGFloat
    private var baselineOffset: CGFloat
}
```

#### 2. PlueMetalRenderer

**Purpose**: Manages the Metal rendering pipeline, directly inspired by Ghostty's approach.

**Key Features**:
- Two-pass rendering: background cells → foreground text
- Font atlas management with CoreText
- Shader pipeline for cells, text, cursor, and selection
- Performance optimizations (dirty region tracking)

**Shader Pipeline**:
1. `cell_bg.metal` - Renders cell background colors
2. `cell_text.metal` - Renders glyphs from font atlas
3. `cursor.metal` - Renders blinking cursor with configurable styles
4. `selection.metal` - Renders text selection overlay

#### 3. PlueTerminalConfig

**Purpose**: Simplified version of Ghostty's configuration system.

**Core Settings**:
```swift
struct PlueTerminalConfig {
    // Visual
    var fontSize: CGFloat = 13
    var fontFamily: String = "SF Mono"
    var backgroundColor: Color = Color(hex: "#282C34")
    var foregroundColor: Color = Color(hex: "#FFFFFF")
    var colorPalette: [Color] = ghosttyDefaultPalette
    
    // Window
    var windowPaddingX: CGFloat = 2
    var windowPaddingY: CGFloat = 2
    var backgroundOpacity: Double = 1.0
    var backgroundBlur: Double = 0
    
    // Behavior
    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = true
    var scrollMultiplier: Double = 3.0
    var copyOnSelect: Bool = true
}
```

#### 4. FFI Bridge Pattern

**Purpose**: Clean interface between Swift and Zig, following Ghostty's patterns.

**Key Functions**:
```swift
// Terminal lifecycle
@_silgen_name("ghostty_surface_new") 
func ghostty_surface_new(config: UnsafePointer<CChar>) -> OpaquePointer

@_silgen_name("ghostty_surface_destroy")
func ghostty_surface_destroy(surface: OpaquePointer)

// Rendering
@_silgen_name("ghostty_surface_render_cells")
func ghostty_surface_render_cells(surface: OpaquePointer, 
                                  viewport: CGRect) -> UnsafePointer<RenderData>

// Input
@_silgen_name("ghostty_surface_key_event")
func ghostty_surface_key_event(surface: OpaquePointer, 
                               event: UnsafePointer<KeyEvent>)
```

### Visual Specifications

#### Color Palette (Ghostty Default)
```
Background: #282C34 (40, 44, 52)
Foreground: #FFFFFF (255, 255, 255)

Black:      #1D1F21    Bright Black:   #666666
Red:        #CC6666    Bright Red:     #D54E53
Green:      #B5BD68    Bright Green:   #B9CA4A
Yellow:     #F0C674    Bright Yellow:  #E7C547
Blue:       #81A2BE    Bright Blue:    #7AA6DA
Magenta:    #B294BB    Bright Magenta: #C397D8
Cyan:       #8ABEB7    Bright Cyan:    #70C0B1
White:      #C5C8C6    Bright White:   #EAEAEA
```

#### Window Styling
- **Padding**: 2pt on all sides
- **Background**: Matches terminal background color
- **macOS Titlebar**: Transparent style
- **Corner Radius**: Native macOS window corners
- **Shadow**: System default shadow

#### Font Rendering
- **Default Size**: 13pt on macOS
- **Cell Dimensions**: Calculated from font metrics
- **Vertical Centering**: Text centered with half line gap above/below
- **Underline Thickness**: 15% of ex-height (min 1px)

### Implementation Phases

#### Phase 1: Core Infrastructure (Week 1)
1. Set up FFI bridge to libghostty
2. Create PlueTerminalSurfaceView with basic Metal layer
3. Implement display link synchronization
4. Basic keyboard input handling

#### Phase 2: Rendering Pipeline (Week 2)
1. Port Metal shaders from Ghostty
2. Implement font atlas generation
3. Two-pass rendering (background → text)
4. Cursor rendering with blinking

#### Phase 3: Input & Interaction (Week 3)
1. Full NSTextInputClient implementation
2. Mouse handling (selection, scrolling)
3. Copy/paste functionality
4. Resize overlay

#### Phase 4: Polish & Configuration (Week 4)
1. Configuration system
2. Error states and recovery
3. Performance optimizations
4. Visual polish to match Ghostty exactly

### Key Differences from Ghostty

**Removed Features**:
- Split panes and dividers
- Tabs and tab management
- Command palette
- Inspector/debug view
- Quick terminal
- Custom shaders
- Image protocol support
- Advanced configuration options

**Simplified Components**:
- Single surface instead of surface collection
- No window management complexity
- Simplified event routing
- Minimal configuration options

### File Structure

```
Sources/plue/Terminal/
├── Core/
│   ├── PlueTerminalSurfaceView.swift      # Main terminal NSView
│   ├── PlueMetalRenderer.swift            # Metal rendering pipeline
│   ├── PlueFontAtlas.swift                # Font texture atlas management
│   └── PlueTerminalFFI.swift              # Ghostty FFI bridge
├── Views/
│   ├── PlueTerminalView.swift             # Main SwiftUI view
│   ├── PlueTerminalSurface.swift          # NSViewRepresentable wrapper
│   └── PlueResizeOverlay.swift            # Resize feedback overlay
├── Models/
│   ├── PlueTerminalConfig.swift           # Configuration
│   ├── PlueTerminalColors.swift           # Color definitions
│   └── PlueTerminalTypes.swift            # Shared types
├── Shaders/
│   ├── PlueTerminal.metal                 # All Metal shaders
│   └── PlueTerminalShaderTypes.h          # Shader type definitions
└── Helpers/
    ├── PlueDisplayLink.swift              # CVDisplayLink wrapper
    └── PlueCoreTextHelpers.swift          # Font metrics utilities
```

### Performance Considerations

1. **Dirty Region Tracking**: Only re-render changed cells
2. **Font Atlas Caching**: Generate glyphs on-demand, cache permanently
3. **Metal Best Practices**: 
   - Triple buffering for smooth rendering
   - Minimize state changes
   - Batch draw calls
4. **Display Link Sync**: Precise frame timing with CVDisplayLink
5. **Memory Management**: Careful FFI memory ownership

### Testing Strategy

1. **Visual Regression Tests**: Screenshot comparisons with Ghostty
2. **Performance Benchmarks**: Frame timing, CPU/GPU usage
3. **Input Tests**: Keyboard/mouse event handling
4. **FFI Safety**: Memory leak detection, crash testing

### Success Metrics

1. **Visual Fidelity**: Pixel-perfect match with Ghostty appearance
2. **Performance**: 60fps scrolling, <5ms input latency
3. **Compatibility**: Full VT100/xterm compatibility via libghostty
4. **Stability**: Zero crashes, graceful error handling

### Appendix: Ghostty Component Mapping

| Ghostty Component | Plue Equivalent | Notes |
|------------------|-----------------|-------|
| SurfaceView | PlueTerminalSurfaceView | Direct port, simplified |
| Surface | PlueTerminalSurface | SwiftUI wrapper |
| SurfaceWrapper | PlueTerminalView | With overlays |
| MetalRenderer | PlueMetalRenderer | Same shader approach |
| Config | PlueTerminalConfig | Subset of options |
| libghostty | libghostty | Reuse directly |

This design ensures we create a terminal that looks and feels exactly like Ghostty while being significantly simpler to implement and maintain.