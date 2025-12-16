package chat

import (
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
	"github.com/williamcory/agent/tui/internal/terminal"
)

// Image display constants
const (
	// Maximum width for image preview in columns
	IMAGE_MAX_WIDTH_COLS = 80

	// Maximum height for image preview in rows
	IMAGE_MAX_HEIGHT_ROWS = 40

	// Supported image MIME types
	MIME_TYPE_PNG  = "image/png"
	MIME_TYPE_JPEG = "image/jpeg"
	MIME_TYPE_JPG  = "image/jpg"
	MIME_TYPE_GIF  = "image/gif"
	MIME_TYPE_WEBP = "image/webp"
	MIME_TYPE_SVG  = "image/svg+xml"
)

// ImageMetadata contains information about an image
type ImageMetadata struct {
	Filename string
	MimeType string
	Width    int
	Height   int
	Size     int64
	URL      string
}

// RenderImage renders an image inline if the terminal supports it, otherwise shows metadata
func RenderImage(url, mimeType, filename string, width int) string {
	// Detect terminal capabilities
	protocol := terminal.DetectImageProtocol()

	// Check if this is a supported image type
	if !isSupportedImageType(mimeType) {
		return renderUnsupportedImage(filename, mimeType)
	}

	// Try to fetch the image data
	data, err := fetchImageData(url)
	if err != nil {
		return renderImageFetchError(filename, mimeType, err)
	}

	// Calculate display dimensions
	displayWidth := IMAGE_MAX_WIDTH_COLS
	if width > 0 && width < displayWidth {
		displayWidth = width
	}

	// Render based on protocol support
	switch protocol {
	case terminal.ImageProtocolITerm2:
		return renderImageITerm2(data, displayWidth, filename, mimeType)

	case terminal.ImageProtocolKitty:
		return renderImageKitty(data, displayWidth, filename, mimeType)

	case terminal.ImageProtocolSixel:
		return renderImageSixel(data, displayWidth, filename, mimeType)

	default:
		// No protocol support - show metadata as fallback
		return renderImageMetadata(filename, mimeType, int64(len(data)))
	}
}

// renderImageITerm2 renders an image using iTerm2 protocol
func renderImageITerm2(data []byte, maxWidth int, filename, mimeType string) string {
	theme := styles.GetCurrentTheme()

	// Render the image
	imageStr := terminal.RenderImageITerm2Auto(data, maxWidth)

	// Add caption with filename and type
	captionStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	caption := captionStyle.Render(fmt.Sprintf("📷 %s (%s, %s)",
		filename, mimeType, formatFileSize(int64(len(data)))))

	return imageStr + "\n" + caption
}

// renderImageKitty renders an image using Kitty protocol
func renderImageKitty(data []byte, maxWidth int, filename, mimeType string) string {
	theme := styles.GetCurrentTheme()

	// Render the image
	imageStr := terminal.RenderImageKittyAuto(data, maxWidth)

	// Add caption
	captionStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	caption := captionStyle.Render(fmt.Sprintf("📷 %s (%s, %s)",
		filename, mimeType, formatFileSize(int64(len(data)))))

	return imageStr + "\n" + caption
}

// renderImageSixel renders an image using Sixel protocol
func renderImageSixel(data []byte, maxWidth int, filename, mimeType string) string {
	// Sixel support is not fully implemented, show metadata instead
	return renderImageMetadata(filename, mimeType, int64(len(data)))
}

// renderImageMetadata renders image metadata as text fallback
func renderImageMetadata(filename, mimeType string, size int64) string {
	theme := styles.GetCurrentTheme()

	style := lipgloss.NewStyle().
		Foreground(theme.Secondary).
		Bold(true)

	// Try to extract dimensions from filename or show placeholder
	// For now, just show size since we don't decode the image
	return style.Render(fmt.Sprintf("📷 %s (%s, %s)",
		filename, mimeType, formatFileSize(size)))
}

// renderUnsupportedImage renders a message for unsupported image types
func renderUnsupportedImage(filename, mimeType string) string {
	theme := styles.GetCurrentTheme()

	style := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	return style.Render(fmt.Sprintf("📎 %s (unsupported type: %s)", filename, mimeType))
}

// renderImageFetchError renders an error message when image fetch fails
func renderImageFetchError(filename, mimeType string, err error) string {
	theme := styles.GetCurrentTheme()

	style := lipgloss.NewStyle().
		Foreground(theme.Error)

	return style.Render(fmt.Sprintf("❌ %s (failed to load: %v)", filename, err))
}

// isSupportedImageType checks if a MIME type is supported for image display
func isSupportedImageType(mimeType string) bool {
	supported := []string{
		MIME_TYPE_PNG,
		MIME_TYPE_JPEG,
		MIME_TYPE_JPG,
		MIME_TYPE_GIF,
		MIME_TYPE_WEBP,
		MIME_TYPE_SVG,
	}

	mimeTypeLower := strings.ToLower(mimeType)
	for _, mt := range supported {
		if mimeTypeLower == mt {
			return true
		}
	}

	return false
}

// fetchImageData fetches image data from a URL
func fetchImageData(url string) ([]byte, error) {
	// Handle data URLs
	if strings.HasPrefix(url, "data:") {
		return fetchDataURL(url)
	}

	// Handle file URLs
	if strings.HasPrefix(url, "file://") {
		return fetchFileURL(url)
	}

	// Handle HTTP/HTTPS URLs
	if strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://") {
		return fetchHTTPURL(url)
	}

	return nil, fmt.Errorf("unsupported URL scheme: %s", url)
}

// fetchDataURL extracts data from a data: URL
func fetchDataURL(url string) ([]byte, error) {
	// data:image/png;base64,iVBORw0KGgo...
	parts := strings.SplitN(url, ",", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid data URL format")
	}

	// For now, we'll return an error since base64 decoding
	// would require importing encoding/base64
	// TODO: Implement base64 decoding for data URLs
	return nil, fmt.Errorf("data URLs not yet supported")
}

// fetchFileURL reads image data from a file: URL
func fetchFileURL(url string) ([]byte, error) {
	// file:///path/to/image.png
	// For now, return an error
	// TODO: Implement file reading
	return nil, fmt.Errorf("file URLs not yet supported")
}

// fetchHTTPURL fetches image data from an HTTP/HTTPS URL
func fetchHTTPURL(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	// Read the response body
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	return data, nil
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

// ExtractFilenameFromURL extracts a filename from a URL
func ExtractFilenameFromURL(url string) string {
	// Try to get filename from URL path
	parts := strings.Split(url, "/")
	if len(parts) > 0 {
		filename := parts[len(parts)-1]
		if filename != "" {
			return filename
		}
	}
	return "image"
}

// IsImageMimeType checks if a MIME type is an image
func IsImageMimeType(mimeType string) bool {
	return strings.HasPrefix(strings.ToLower(mimeType), "image/")
}

// GetImageExtension returns the file extension for a MIME type
func GetImageExtension(mimeType string) string {
	switch strings.ToLower(mimeType) {
	case MIME_TYPE_PNG:
		return ".png"
	case MIME_TYPE_JPEG, MIME_TYPE_JPG:
		return ".jpg"
	case MIME_TYPE_GIF:
		return ".gif"
	case MIME_TYPE_WEBP:
		return ".webp"
	case MIME_TYPE_SVG:
		return ".svg"
	default:
		return ""
	}
}

// SanitizeFilename ensures a filename is safe to display
func SanitizeFilename(filename string) string {
	// Remove path separators
	filename = filepath.Base(filename)

	// Truncate if too long
	const MAX_FILENAME_LEN = 50
	if len(filename) > MAX_FILENAME_LEN {
		ext := filepath.Ext(filename)
		base := filename[:len(filename)-len(ext)]
		if len(base) > MAX_FILENAME_LEN-len(ext)-3 {
			base = base[:MAX_FILENAME_LEN-len(ext)-3]
		}
		filename = base + "..." + ext
	}

	return filename
}
