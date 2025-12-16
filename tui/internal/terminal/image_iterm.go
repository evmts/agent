package terminal

import (
	"encoding/base64"
	"fmt"
)

// ITerm2 image protocol constants
const (
	// Maximum size for inline images in iTerm2
	ITERM2_MAX_WIDTH  = 80  // columns
	ITERM2_MAX_HEIGHT = 40  // rows
)

// RenderImageITerm2 renders an image using iTerm2's inline image protocol
// Uses OSC 1337 escape sequence: ESC ] 1337 ; File = [arguments] : base64-encoded-file-contents ^G
func RenderImageITerm2(data []byte, width, height int) string {
	// Encode image data as base64
	encoded := base64.StdEncoding.EncodeToString(data)

	// Build the iTerm2 inline image escape sequence
	// Format: \x1b]1337;File=inline=1;width={width};height={height}:{base64data}\x07
	// width/height can be specified in different units:
	// - Just a number: number of cells (characters)
	// - Npx: number of pixels
	// - N%: percentage of session width/height
	// - auto: preserve aspect ratio

	// Use character cells for width, auto for height to preserve aspect ratio
	return fmt.Sprintf("\x1b]1337;File=inline=1;width=%d;preserveAspectRatio=1:%s\x07",
		width, encoded)
}

// RenderImageITerm2WithSize renders an image with specific dimensions
func RenderImageITerm2WithSize(data []byte, widthCols, heightRows int) string {
	encoded := base64.StdEncoding.EncodeToString(data)

	// Specify both width and height in character cells
	return fmt.Sprintf("\x1b]1337;File=inline=1;width=%d;height=%d:%s\x07",
		widthCols, heightRows, encoded)
}

// RenderImageITerm2Auto renders an image with automatic sizing
func RenderImageITerm2Auto(data []byte, maxWidth int) string {
	encoded := base64.StdEncoding.EncodeToString(data)

	// Use width constraint with automatic height
	return fmt.Sprintf("\x1b]1337;File=inline=1;width=%d;preserveAspectRatio=1:%s\x07",
		maxWidth, encoded)
}

// RenderImageITerm2Pixels renders an image using pixel dimensions
func RenderImageITerm2Pixels(data []byte, widthPx, heightPx int) string {
	encoded := base64.StdEncoding.EncodeToString(data)

	// Specify dimensions in pixels
	return fmt.Sprintf("\x1b]1337;File=inline=1;width=%dpx;height=%dpx:%s\x07",
		widthPx, heightPx, encoded)
}

// FormatITerm2Image creates a complete iTerm2 image display with optional caption
func FormatITerm2Image(data []byte, maxWidth int, caption string) string {
	imageStr := RenderImageITerm2Auto(data, maxWidth)

	if caption != "" {
		return imageStr + "\n" + caption
	}

	return imageStr
}
