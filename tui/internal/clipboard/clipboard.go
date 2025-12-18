package clipboard

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
)

// ImageData represents image data from the clipboard.
type ImageData struct {
	Data   []byte
	Format string // "png", "jpeg", "gif", "webp"
}

// GetImage retrieves image from clipboard.
// Returns nil, nil if no image is available (not an error).
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
	// First check if there's an image in the clipboard
	checkCmd := exec.Command("osascript", "-e", "try", "-e", "set theImage to the clipboard as «class PNGf»", "-e", "return true", "-e", "on error", "-e", "return false", "-e", "end try")
	output, err := checkCmd.Output()
	if err != nil || string(output) != "true\n" {
		// No image in clipboard, not an error
		return nil, nil
	}

	// Get the image data
	cmd := exec.Command("osascript", "-e", "set pngData to the clipboard as «class PNGf»", "-e", "return pngData")
	data, err := cmd.Output()
	if err != nil || len(data) == 0 {
		return nil, nil
	}

	return &ImageData{
		Data:   data,
		Format: "png",
	}, nil
}

func getImageLinux() (*ImageData, error) {
	// Try xclip first (X11)
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

	// No image found, not an error
	return nil, nil
}

func getImageWindows() (*ImageData, error) {
	// Windows clipboard support can be added later
	// For now, return nil (no image available)
	return nil, nil
}

// SaveToTemp saves image data to a temp file.
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
