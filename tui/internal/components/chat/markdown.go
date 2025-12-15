package chat

import (
	"sync"

	"github.com/charmbracelet/glamour"
)

var (
	renderer *glamour.TermRenderer
	mu       sync.RWMutex
	enabled  = true // Markdown rendering enabled by default
)

// InitMarkdown initializes the markdown renderer with the given width
func InitMarkdown(width int) error {
	mu.Lock()
	defer mu.Unlock()

	r, err := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(width),
	)
	if err != nil {
		return err
	}
	renderer = r
	return nil
}

// RenderMarkdown renders markdown content to terminal format
// Falls back to plain text if rendering fails or is disabled
func RenderMarkdown(content string) string {
	mu.RLock()
	defer mu.RUnlock()

	if !enabled || renderer == nil {
		return content
	}

	out, err := renderer.Render(content)
	if err != nil {
		return content
	}
	return out
}

// SetMarkdownEnabled enables or disables markdown rendering
func SetMarkdownEnabled(enable bool) {
	mu.Lock()
	defer mu.Unlock()
	enabled = enable
}

// IsMarkdownEnabled returns whether markdown rendering is enabled
func IsMarkdownEnabled() bool {
	mu.RLock()
	defer mu.RUnlock()
	return enabled
}

// ToggleMarkdown toggles markdown rendering on/off
func ToggleMarkdown() bool {
	mu.Lock()
	defer mu.Unlock()
	enabled = !enabled
	return enabled
}
