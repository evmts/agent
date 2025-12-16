package app

import (
	"strings"

	"github.com/williamcory/agent/tui/internal/config"
	"github.com/williamcory/agent/tui/internal/notification"
)

// copyToClipboard copies text to system clipboard
func copyToClipboard(text string) error {
	// Use pbcopy on macOS, xclip on Linux
	// For now, just return nil - clipboard integration would require os/exec
	_ = text
	return nil
}

// extractCodeBlocks extracts code blocks from markdown text
func extractCodeBlocks(text string) string {
	// Simple extraction of code blocks between ``` markers
	var result []string
	lines := strings.Split(text, "\n")
	inCodeBlock := false
	var currentBlock []string

	for _, line := range lines {
		if strings.HasPrefix(line, "```") {
			if inCodeBlock {
				// End of code block
				if len(currentBlock) > 0 {
					result = append(result, strings.Join(currentBlock, "\n"))
				}
				currentBlock = nil
				inCodeBlock = false
			} else {
				// Start of code block
				inCodeBlock = true
			}
		} else if inCodeBlock {
			currentBlock = append(currentBlock, line)
		}
	}

	return strings.Join(result, "\n\n")
}

// convertNotificationPreferences converts config.NotificationPreferences to notification.NotificationConfig
func convertNotificationPreferences(prefs config.NotificationPreferences) notification.NotificationConfig {
	var soundType notification.SoundType
	switch prefs.SoundType {
	case "bell":
		soundType = notification.SoundBell
	case "chime":
		soundType = notification.SoundChime
	case "custom":
		soundType = notification.SoundCustom
	case "visual":
		soundType = notification.SoundBell // Will use visual flash mode
	default:
		soundType = notification.SoundBell
	}

	return notification.NotificationConfig{
		Enabled:              prefs.Enabled,
		SoundType:            soundType,
		Volume:               prefs.Volume,
		CustomPath:           prefs.CustomPath,
		VisualFlash:          prefs.SoundType == "visual",
		NotifyOnComplete:     prefs.NotifyOnComplete,
		NotifyOnError:        prefs.NotifyOnError,
		NotifyOnConfirmation: prefs.NotifyOnConfirmation,
	}
}
