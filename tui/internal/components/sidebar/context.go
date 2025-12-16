package sidebar

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	// CLAUDE_MD_FILENAME is the name of the context file
	CLAUDE_MD_FILENAME = "CLAUDE.md"
	// MAX_PREVIEW_LINES is the maximum number of lines to show in the sidebar preview
	MAX_PREVIEW_LINES = 15
)

// ContextSource represents a loaded CLAUDE.md file
type ContextSource struct {
	Path     string
	Content  string
	Priority int       // Lower = higher priority
	Exists   bool
	ModTime  time.Time
}

// ClaudeMdContext holds all loaded CLAUDE.md sources
type ClaudeMdContext struct {
	Sources      []ContextSource
	PrimaryIndex int // Index of the highest priority source that exists
}

// ClaudeMdPaths returns the search paths for CLAUDE.md in priority order
func ClaudeMdPaths() []string {
	homeDir, _ := os.UserHomeDir()
	return []string{
		filepath.Join(".claude", CLAUDE_MD_FILENAME),  // Project .claude directory (priority 0)
		CLAUDE_MD_FILENAME,                             // Project root (priority 1)
		filepath.Join(homeDir, ".claude", CLAUDE_MD_FILENAME), // Global user config (priority 2)
	}
}

// LoadClaudeMdContext loads all CLAUDE.md files from the standard locations
func LoadClaudeMdContext() ClaudeMdContext {
	paths := ClaudeMdPaths()
	sources := make([]ContextSource, len(paths))
	primaryIndex := -1

	for i, path := range paths {
		source := ContextSource{
			Path:     path,
			Priority: i,
			Exists:   false,
		}

		// Try to read the file
		if content, modTime, err := readClaudeMd(path); err == nil {
			source.Content = content
			source.Exists = true
			source.ModTime = modTime
			// Track the first (highest priority) source that exists
			if primaryIndex == -1 {
				primaryIndex = i
			}
		}

		sources[i] = source
	}

	return ClaudeMdContext{
		Sources:      sources,
		PrimaryIndex: primaryIndex,
	}
}

// readClaudeMd reads a CLAUDE.md file and returns its content and modification time
func readClaudeMd(path string) (string, time.Time, error) {
	// Expand home directory if needed
	if strings.HasPrefix(path, "~") {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return "", time.Time{}, err
		}
		path = filepath.Join(homeDir, path[1:])
	}

	// Read file info for modification time
	info, err := os.Stat(path)
	if err != nil {
		return "", time.Time{}, err
	}

	// Read file content
	content, err := os.ReadFile(path)
	if err != nil {
		return "", time.Time{}, err
	}

	return string(content), info.ModTime(), nil
}

// GetPrimarySource returns the highest priority source that exists, or nil if none exist
func (c *ClaudeMdContext) GetPrimarySource() *ContextSource {
	if c.PrimaryIndex >= 0 && c.PrimaryIndex < len(c.Sources) {
		return &c.Sources[c.PrimaryIndex]
	}
	return nil
}

// HasAnySource returns true if at least one CLAUDE.md file was found
func (c *ClaudeMdContext) HasAnySource() bool {
	return c.PrimaryIndex >= 0
}

// GetPreview returns a preview of the primary source (first N lines)
func (c *ClaudeMdContext) GetPreview() string {
	source := c.GetPrimarySource()
	if source == nil {
		return ""
	}

	lines := strings.Split(source.Content, "\n")
	if len(lines) <= MAX_PREVIEW_LINES {
		return source.Content
	}

	// Take first MAX_PREVIEW_LINES and add ellipsis
	preview := strings.Join(lines[:MAX_PREVIEW_LINES], "\n")
	preview += "\n..."
	return preview
}

// GetLineCount returns the total line count of the primary source
func (c *ClaudeMdContext) GetLineCount() int {
	source := c.GetPrimarySource()
	if source == nil {
		return 0
	}
	return len(strings.Split(source.Content, "\n"))
}

// GetFormattedPath returns a user-friendly path representation
func (c *ClaudeMdContext) GetFormattedPath() string {
	source := c.GetPrimarySource()
	if source == nil {
		return ""
	}

	path := source.Path
	// Replace home directory with ~
	if homeDir, err := os.UserHomeDir(); err == nil {
		if strings.HasPrefix(path, homeDir) {
			path = "~" + strings.TrimPrefix(path, homeDir)
		}
	}

	return path
}

// GetRelativeUpdateTime returns a human-readable relative time since last update
func (c *ClaudeMdContext) GetRelativeUpdateTime() string {
	source := c.GetPrimarySource()
	if source == nil {
		return ""
	}

	now := time.Now()
	diff := now.Sub(source.ModTime)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		minutes := int(diff.Minutes())
		if minutes == 1 {
			return "1 min ago"
		}
		return formatDuration(minutes, "min")
	case diff < 24*time.Hour:
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return formatDuration(hours, "hour")
	case diff < 7*24*time.Hour:
		days := int(diff.Hours() / 24)
		if days == 1 {
			return "1 day ago"
		}
		return formatDuration(days, "day")
	default:
		return source.ModTime.Format("Jan 2")
	}
}

// formatDuration formats a duration value with a unit
func formatDuration(value int, unit string) string {
	return strings.Join([]string{formatIntToStr(value), unit + "s", "ago"}, " ")
}

// formatIntToStr converts an integer to string using fmt
func formatIntToStr(n int) string {
	// Convert int to string without importing fmt
	if n == 0 {
		return "0"
	}

	// Simple integer to string conversion
	var digits []byte
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}
