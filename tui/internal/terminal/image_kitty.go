package terminal

import (
	"encoding/base64"
	"fmt"
	"strings"
)

// Kitty graphics protocol constants
const (
	// Maximum chunk size for Kitty protocol (4096 bytes is safe)
	KITTY_CHUNK_SIZE = 4096

	// Maximum dimensions
	KITTY_MAX_WIDTH  = 80  // columns
	KITTY_MAX_HEIGHT = 40  // rows
)

// RenderImageKitty renders an image using Kitty's graphics protocol
// Uses APC escape sequence with base64 data
// Format: ESC _G<control data>;ESC \ESC _G<payload data>;ESC \
func RenderImageKitty(data []byte, widthCols, heightCols int) string {
	// Encode image data as base64
	encoded := base64.StdEncoding.EncodeToString(data)

	// For small images, send in one chunk
	if len(encoded) <= KITTY_CHUNK_SIZE {
		// Single transmission
		// a=T: direct transmission
		// f=100: PNG format (auto-detect)
		// c=widthCols: width in columns
		// r=heightCols: height in rows
		ctrl := fmt.Sprintf("a=T,f=100,c=%d,r=%d", widthCols, heightCols)
		return fmt.Sprintf("\x1b_G%s;%s\x1b\\", ctrl, encoded)
	}

	// For large images, chunk the data
	return renderImageKittyChunked(encoded, widthCols, heightCols)
}

// renderImageKittyChunked sends a large image in multiple chunks
func renderImageKittyChunked(encodedData string, widthCols, heightCols int) string {
	var result strings.Builder

	chunks := chunkString(encodedData, KITTY_CHUNK_SIZE)

	for i, chunk := range chunks {
		var ctrl string
		if i == 0 {
			// First chunk: include format and size info
			// m=1: more chunks to follow
			ctrl = fmt.Sprintf("a=T,f=100,c=%d,r=%d,m=1", widthCols, heightCols)
		} else if i == len(chunks)-1 {
			// Last chunk: no more chunks
			// m=0: this is the last chunk
			ctrl = "m=0"
		} else {
			// Middle chunks
			// m=1: more chunks to follow
			ctrl = "m=1"
		}

		result.WriteString(fmt.Sprintf("\x1b_G%s;%s\x1b\\", ctrl, chunk))
	}

	return result.String()
}

// RenderImageKittyAuto renders an image with automatic sizing
func RenderImageKittyAuto(data []byte, maxWidth int) string {
	// Use maxWidth and let Kitty determine height based on aspect ratio
	return RenderImageKitty(data, maxWidth, 0)
}

// RenderImageKittyPixels renders an image using pixel dimensions
func RenderImageKittyPixels(data []byte, widthPx, heightPx int) string {
	encoded := base64.StdEncoding.EncodeToString(data)

	// Use pixel dimensions instead of columns/rows
	// w=widthPx: width in pixels
	// h=heightPx: height in pixels
	ctrl := fmt.Sprintf("a=T,f=100,w=%d,h=%d", widthPx, heightPx)

	if len(encoded) <= KITTY_CHUNK_SIZE {
		return fmt.Sprintf("\x1b_G%s;%s\x1b\\", ctrl, encoded)
	}

	// For large images, chunk the data
	return renderImageKittyPixelsChunked(encoded, widthPx, heightPx)
}

// renderImageKittyPixelsChunked sends a large image with pixel dimensions in chunks
func renderImageKittyPixelsChunked(encodedData string, widthPx, heightPx int) string {
	var result strings.Builder

	chunks := chunkString(encodedData, KITTY_CHUNK_SIZE)

	for i, chunk := range chunks {
		var ctrl string
		if i == 0 {
			ctrl = fmt.Sprintf("a=T,f=100,w=%d,h=%d,m=1", widthPx, heightPx)
		} else if i == len(chunks)-1 {
			ctrl = "m=0"
		} else {
			ctrl = "m=1"
		}

		result.WriteString(fmt.Sprintf("\x1b_G%s;%s\x1b\\", ctrl, chunk))
	}

	return result.String()
}

// FormatKittyImage creates a complete Kitty image display with optional caption
func FormatKittyImage(data []byte, maxWidth int, caption string) string {
	imageStr := RenderImageKittyAuto(data, maxWidth)

	if caption != "" {
		return imageStr + "\n" + caption
	}

	return imageStr
}

// chunkString splits a string into chunks of specified size
func chunkString(s string, chunkSize int) []string {
	if len(s) <= chunkSize {
		return []string{s}
	}

	var chunks []string
	for i := 0; i < len(s); i += chunkSize {
		end := i + chunkSize
		if end > len(s) {
			end = len(s)
		}
		chunks = append(chunks, s[i:end])
	}

	return chunks
}

// DeleteImageKitty sends a command to delete a displayed image
func DeleteImageKitty(imageID int) string {
	// a=d: delete image
	// d=i: delete by ID
	// i=imageID: the image ID to delete
	return fmt.Sprintf("\x1b_Ga=d,d=i,i=%d\x1b\\", imageID)
}

// DeleteAllImagesKitty sends a command to delete all displayed images
func DeleteAllImagesKitty() string {
	// a=d: delete image
	// d=a: delete all
	return "\x1b_Ga=d,d=a\x1b\\"
}
