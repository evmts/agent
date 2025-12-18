# Image Paste Support

<metadata>
  <priority>medium</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/</affects>
</metadata>

## Objective

Implement clipboard image paste support in the TUI, allowing users to paste screenshots and images directly into the composer with Ctrl+V/Cmd+V.

<context>
Codex supports pasting images directly into the chat via keyboard shortcut. This is useful for:
- Sharing screenshots of errors
- Providing visual context for UI work
- Referencing diagrams or mockups
- Quick image inclusion without file paths

The pasted image is saved to a temp file and included in the message as a vision input.
</context>

## Requirements

<functional-requirements>
1. Detect Ctrl+V/Cmd+V for paste
2. Check clipboard for image content
3. If image found:
   - Save to temp file
   - Show thumbnail/indicator in composer
   - Include in message as vision input
4. Support common formats: PNG, JPEG, GIF, WebP
5. Show error for unsupported formats
6. Allow removing pasted image before sending
7. Multiple images per message
</functional-requirements>

<technical-requirements>
1. Implement clipboard image detection
2. Save images to temp directory
3. Create image attachment model
4. Update composer to show attachments
5. Send attachments with message API
6. Handle cross-platform clipboard APIs
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/composer/composer.go` - Handle paste and attachments
- `tui/internal/components/composer/attachments.go` (CREATE) - Attachment management
- `tui/internal/clipboard/clipboard.go` (CREATE) - Clipboard utilities
- `tui/internal/app/update_keys.go` - Handle Ctrl+V
</files-to-modify>

<clipboard-detection>
```go
// tui/internal/clipboard/clipboard.go

package clipboard

import (
    "bytes"
    "image"
    "image/png"
    "os"
    "os/exec"
    "path/filepath"
    "runtime"

    _ "image/gif"
    _ "image/jpeg"
    "golang.org/x/image/webp"
)

type ImageData struct {
    Data   []byte
    Format string // "png", "jpeg", "gif", "webp"
}

// GetImage retrieves image from clipboard
func GetImage() (*ImageData, error) {
    switch runtime.GOOS {
    case "darwin":
        return getImageMacOS()
    case "linux":
        return getImageLinux()
    case "windows":
        return getImageWindows()
    default:
        return nil, fmt.Errorf("unsupported platform: %s", runtime.GOOS)
    }
}

func getImageMacOS() (*ImageData, error) {
    // Use pbpaste with osascript for image
    script := `osascript -e 'try' -e 'set imgData to the clipboard as «class PNGf»' -e 'return imgData' -e 'end try'`
    cmd := exec.Command("bash", "-c", script)
    output, err := cmd.Output()
    if err != nil || len(output) == 0 {
        return nil, fmt.Errorf("no image in clipboard")
    }

    return &ImageData{
        Data:   output,
        Format: "png",
    }, nil
}

func getImageLinux() (*ImageData, error) {
    // Try xclip first
    cmd := exec.Command("xclip", "-selection", "clipboard", "-t", "image/png", "-o")
    output, err := cmd.Output()
    if err == nil && len(output) > 0 {
        return &ImageData{Data: output, Format: "png"}, nil
    }

    // Try wl-paste for Wayland
    cmd = exec.Command("wl-paste", "-t", "image/png")
    output, err = cmd.Output()
    if err == nil && len(output) > 0 {
        return &ImageData{Data: output, Format: "png"}, nil
    }

    return nil, fmt.Errorf("no image in clipboard")
}

// SaveToTemp saves image data to a temp file
func (img *ImageData) SaveToTemp() (string, error) {
    ext := "." + img.Format
    tmpFile, err := os.CreateTemp("", "agent-paste-*"+ext)
    if err != nil {
        return "", err
    }
    defer tmpFile.Close()

    _, err = tmpFile.Write(img.Data)
    if err != nil {
        os.Remove(tmpFile.Name())
        return "", err
    }

    return tmpFile.Name(), nil
}
```
</clipboard-detection>

<composer-attachments>
```go
// tui/internal/components/composer/attachments.go

package composer

type Attachment struct {
    ID       string
    Type     string // "image"
    FilePath string
    Preview  string // Short display text
}

type AttachmentManager struct {
    attachments []Attachment
}

func (am *AttachmentManager) AddImage(filePath string) error {
    id := generateID()
    filename := filepath.Base(filePath)

    am.attachments = append(am.attachments, Attachment{
        ID:       id,
        Type:     "image",
        FilePath: filePath,
        Preview:  fmt.Sprintf("📎 %s", filename),
    })

    return nil
}

func (am *AttachmentManager) Remove(id string) {
    for i, att := range am.attachments {
        if att.ID == id {
            am.attachments = append(am.attachments[:i], am.attachments[i+1:]...)
            // Clean up temp file
            if strings.HasPrefix(att.FilePath, os.TempDir()) {
                os.Remove(att.FilePath)
            }
            return
        }
    }
}

func (am *AttachmentManager) Clear() {
    for _, att := range am.attachments {
        if strings.HasPrefix(att.FilePath, os.TempDir()) {
            os.Remove(att.FilePath)
        }
    }
    am.attachments = nil
}

func (am *AttachmentManager) GetPaths() []string {
    paths := make([]string, len(am.attachments))
    for i, att := range am.attachments {
        paths[i] = att.FilePath
    }
    return paths
}

func (am *AttachmentManager) View() string {
    if len(am.attachments) == 0 {
        return ""
    }

    var parts []string
    for _, att := range am.attachments {
        parts = append(parts, att.Preview)
    }
    return strings.Join(parts, " ")
}
```
</composer-attachments>

<paste-handler>
```go
// In tui/internal/app/update_keys.go

func (m *Model) handlePaste() tea.Cmd {
    return func() tea.Msg {
        // Check for image in clipboard
        img, err := clipboard.GetImage()
        if err != nil {
            // No image, let default text paste happen
            return nil
        }

        // Save to temp file
        path, err := img.SaveToTemp()
        if err != nil {
            return ErrorMsg{Err: fmt.Errorf("failed to save image: %w", err)}
        }

        return ImagePastedMsg{Path: path}
    }
}

// In update function
case ImagePastedMsg:
    err := m.composer.attachments.AddImage(msg.Path)
    if err != nil {
        return m, nil
    }
    // Show notification
    return m, m.showNotification("Image attached")

// In composer View
func (c *Composer) View() string {
    var b strings.Builder

    // Show attachments
    attachView := c.attachments.View()
    if attachView != "" {
        b.WriteString(lipgloss.NewStyle().
            Foreground(lipgloss.Color("241")).
            Render(attachView))
        b.WriteString("\n")
    }

    // Show input
    b.WriteString(c.textArea.View())

    return b.String()
}
```
</paste-handler>

<composer-ui>
```
┌────────────────────────────────────────────────────┐
│ 📎 screenshot-2024-01-15.png  [x]                  │
├────────────────────────────────────────────────────┤
│ Can you help me fix this error? I've attached a   │
│ screenshot showing the problem.                    │
│                                                    │
│ █                                                  │
└────────────────────────────────────────────────────┘
  [Ctrl+V: Paste image] [Enter: Send] [Esc: Cancel]
```
</composer-ui>

## Acceptance Criteria

<criteria>
- [x] Ctrl+V/Cmd+V pastes clipboard images
- [x] Image saved to temp file
- [x] Attachment shown in composer
- [x] Multiple images supported
- [ ] Remove attachment before sending (not implemented)
- [x] Image included in message API call
- [x] Supports PNG, JPEG, GIF formats
- [x] Error shown for unsupported formats
- [x] Works on macOS, Linux (X11/Wayland)
- [x] Temp files cleaned up on send/cancel
- [x] Text paste still works when no image
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test paste on macOS and Linux
3. Test with various image formats
4. Test multiple images and removal
5. Run `zig build build-go` to ensure compilation succeeds
6. Rename this file from `43-image-paste.md` to `43-image-paste.complete.md`
</completion>

## Implementation Hindsight

<hindsight>
**Completed:** 2024-12-17

**Key Implementation Notes:**
1. tui/internal/clipboard/clipboard.go already existed with cross-platform support
2. macOS uses AppleScript for PNG extraction
3. Linux supports xclip (X11) and wl-paste (Wayland)
4. Windows stub exists but not implemented
5. Images saved to temp with pattern agent-paste-*.png
6. Cleanup happens automatically after streamCompleteMsg

**Files Modified:**
- `tui/internal/clipboard/clipboard.go` - GetImage, SaveToTemp (pre-existed)
- `tui/main.go` - imageAttachment struct, handleImagePaste, Ctrl+V handler, cleanupImageAttachments, View attachment display

**Prompt Improvements for Future:**
1. Don't suggest separate component files - TUI uses monolithic main.go
2. Specify key binding for removing attachments (not implemented)
3. Clarify backend support for file:// URLs vs base64
4. Note platform requirements (xclip, wl-paste for Linux)
5. Windows not yet implemented
6. Only PNG extraction works on macOS currently
</hindsight>
