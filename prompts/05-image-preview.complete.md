# Image Preview Support

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>tui/internal/components/chat/</affects>
</metadata>

## Objective

Display image previews inline in the terminal chat interface, supporting modern terminal image protocols (iTerm2, Kitty, Sixel).

<context>
Claude Code can display images directly in the terminal when:
- Users attach images to their messages
- The agent generates diagrams or screenshots
- Reading image files from the filesystem

This is achieved using terminal-specific image protocols. The implementation should gracefully degrade to showing image metadata when the terminal doesn't support images.
</context>

## Requirements

<functional-requirements>
1. Detect terminal image protocol support (iTerm2, Kitty, Sixel, or none)
2. Display inline image previews for:
   - User-attached images
   - Images referenced in file parts
   - Screenshot tool outputs
3. Show image metadata as fallback: `📷 image.png (1920x1080, 245KB)`
4. Limit preview size to reasonable dimensions (max 80 cols width)
5. Support common formats: PNG, JPG, GIF, WebP, SVG
6. Allow opening full image in external viewer
</functional-requirements>

<technical-requirements>
1. Implement terminal capability detection
2. Add image rendering for each protocol:
   - iTerm2: OSC 1337 escape sequence
   - Kitty: APC escape sequence with base64
   - Sixel: Sixel graphics protocol
3. Create image scaling/resizing logic
4. Add fallback text display
5. Handle image loading errors gracefully
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/chat/image.go` - New image rendering component
- `tui/internal/components/chat/message.go` - Update renderFilePart
- `tui/internal/terminal/capabilities.go` - Terminal detection
- `tui/internal/terminal/image_iterm.go` - iTerm2 protocol
- `tui/internal/terminal/image_kitty.go` - Kitty protocol
</files-to-modify>

<terminal-detection>
```go
type ImageProtocol int

const (
    ImageProtocolNone ImageProtocol = iota
    ImageProtocolITerm2
    ImageProtocolKitty
    ImageProtocolSixel
)

func DetectImageProtocol() ImageProtocol {
    term := os.Getenv("TERM")
    termProgram := os.Getenv("TERM_PROGRAM")
    kittyPid := os.Getenv("KITTY_PID")

    if kittyPid != "" {
        return ImageProtocolKitty
    }
    if termProgram == "iTerm.app" {
        return ImageProtocolITerm2
    }
    // Check for sixel support via DECRQSS
    if checkSixelSupport() {
        return ImageProtocolSixel
    }
    return ImageProtocolNone
}
```
</terminal-detection>

<iterm2-protocol>
```go
func RenderImageITerm2(data []byte, width, height int) string {
    encoded := base64.StdEncoding.EncodeToString(data)

    // iTerm2 inline image protocol
    // OSC 1337 ; File=[args] : base64data ST
    return fmt.Sprintf("\x1b]1337;File=inline=1;width=%d;height=%d:%s\x07",
        width, height, encoded)
}
```
</iterm2-protocol>

<example-ui>
```
# With image support:
┌─────────────────────────────────────┐
│ You                                 │
│ Here's a screenshot of the bug:     │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │  [Actual image rendered here]  │ │
│ │                                 │ │
│ │     (Terminal image preview)    │ │
│ └─────────────────────────────────┘ │
│ 📷 screenshot.png (1920x1080, 245KB)│
│ [Press O to open in viewer]         │
└─────────────────────────────────────┘

# Without image support (fallback):
┌─────────────────────────────────────┐
│ You                                 │
│ Here's a screenshot of the bug:     │
│                                     │
│ 📷 screenshot.png                   │
│    Dimensions: 1920x1080            │
│    Size: 245KB                      │
│    Format: PNG                      │
│ [Press O to open in viewer]         │
└─────────────────────────────────────┘
```
</example-ui>

## Acceptance Criteria

<criteria>
- [ ] Terminal image protocol auto-detected
- [ ] Images render inline in supported terminals
- [ ] Fallback metadata shown in unsupported terminals
- [ ] Image scaled to fit terminal width
- [ ] Keybinding opens image in external viewer
- [ ] Common image formats supported (PNG, JPG, GIF)
- [ ] Large images don't crash or hang the TUI
- [ ] Loading errors show graceful error message
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test in iTerm2, Kitty, and basic terminal
4. Rename this file from `05-image-preview.md` to `05-image-preview.complete.md`
</completion>
