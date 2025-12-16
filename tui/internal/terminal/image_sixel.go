package terminal

import (
	"fmt"
)

// Sixel graphics protocol constants
const (
	// Sixel color palette size (typically 256 colors)
	SIXEL_PALETTE_SIZE = 256

	// Maximum dimensions for Sixel
	SIXEL_MAX_WIDTH  = 800  // pixels (reasonable for terminal)
	SIXEL_MAX_HEIGHT = 600  // pixels
)

// RenderImageSixel renders an image using the Sixel graphics protocol
// Note: This is a placeholder implementation. Full Sixel encoding requires
// image processing library to convert images to Sixel format.
// For a production implementation, you would need to:
// 1. Decode the image data
// 2. Scale/resize if needed
// 3. Quantize colors to Sixel palette
// 4. Encode as Sixel data
func RenderImageSixel(data []byte, width, height int) string {
	// Sixel sequence format:
	// DCS Pn1 ; Pn2 ; Pn3 q s...s ST
	// DCS = ESC P
	// ST = ESC \
	// Pn1: aspect ratio (0 = default)
	// Pn2: background color handling (0-2)
	// Pn3: horizontal grid size

	// For now, return a placeholder that indicates Sixel is not fully implemented
	// A full implementation would require image decoding and Sixel encoding
	return fmt.Sprintf("[Sixel image: %dx%d - requires image processing library]", width, height)
}

// RenderImageSixelPlaceholder creates a text placeholder for Sixel images
// This is used when Sixel is detected but not fully implemented
func RenderImageSixelPlaceholder(filename string, width, height int, size int64) string {
	return fmt.Sprintf("📷 %s (%dx%d, %s) [Sixel support coming soon]",
		filename, width, height, formatFileSize(size))
}

// formatFileSize formats a file size in bytes to human-readable format
func formatFileSize(bytes int64) string {
	const (
		KB = 1024
		MB = KB * 1024
		GB = MB * 1024
	)

	switch {
	case bytes >= GB:
		return fmt.Sprintf("%.1fGB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.1fMB", float64(bytes)/float64(MB))
	case bytes >= KB:
		return fmt.Sprintf("%.1fKB", float64(bytes)/float64(KB))
	default:
		return fmt.Sprintf("%dB", bytes)
	}
}

// Note: Full Sixel implementation would require:
// - Image decoding (using image/png, image/jpeg, etc.)
// - Image scaling/resizing
// - Color quantization to Sixel palette
// - Sixel encoding
//
// This would likely require external dependencies like:
// - github.com/nfnt/resize for image resizing
// - github.com/mattn/go-sixel for Sixel encoding
//
// For now, we'll use fallback text display for Sixel terminals
// until a full implementation is needed.
