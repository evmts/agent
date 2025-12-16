package terminal

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// ImageProtocol represents the supported terminal image display protocol
type ImageProtocol int

const (
	ImageProtocolNone ImageProtocol = iota
	ImageProtocolITerm2
	ImageProtocolKitty
	ImageProtocolSixel
)

// String returns the string representation of the protocol
func (p ImageProtocol) String() string {
	switch p {
	case ImageProtocolITerm2:
		return "iTerm2"
	case ImageProtocolKitty:
		return "Kitty"
	case ImageProtocolSixel:
		return "Sixel"
	default:
		return "None"
	}
}

// DetectImageProtocol detects which image protocol the terminal supports
func DetectImageProtocol() ImageProtocol {
	// Check environment variables for terminal identification
	term := os.Getenv("TERM")
	termProgram := os.Getenv("TERM_PROGRAM")
	kittyPid := os.Getenv("KITTY_PID")

	// Kitty terminal (highest priority as it sets KITTY_PID)
	if kittyPid != "" {
		return ImageProtocolKitty
	}

	// iTerm2 terminal
	if termProgram == "iTerm.app" {
		return ImageProtocolITerm2
	}

	// Check for Sixel support
	if checkSixelSupport(term) {
		return ImageProtocolSixel
	}

	return ImageProtocolNone
}

// checkSixelSupport checks if the terminal supports Sixel graphics
func checkSixelSupport(term string) bool {
	// Known terminals with Sixel support
	sixelTerms := []string{
		"xterm",
		"mlterm",
		"wezterm",
		"foot",
		"contour",
		"yaft",
	}

	termLower := strings.ToLower(term)
	for _, st := range sixelTerms {
		if strings.Contains(termLower, st) {
			// Try to query terminal for Sixel support using DA1 query
			// This is more reliable than just checking TERM
			if querySixelSupport() {
				return true
			}
		}
	}

	return false
}

// querySixelSupport queries the terminal for Sixel support using Device Attributes
// Returns true if Sixel is supported
func querySixelSupport() bool {
	// For now, we'll just return true if we're in a known Sixel terminal
	// A proper implementation would send CSI c and parse the response
	// This is complex and requires raw terminal mode, so we'll skip it for now
	return false
}

// TerminalCapabilities holds information about terminal capabilities
type TerminalCapabilities struct {
	ImageProtocol ImageProtocol
	ColorDepth    int
	Width         int
	Height        int
}

// DetectCapabilities detects all terminal capabilities
func DetectCapabilities() TerminalCapabilities {
	caps := TerminalCapabilities{
		ImageProtocol: DetectImageProtocol(),
		ColorDepth:    detectColorDepth(),
		Width:         80,  // Default
		Height:        24,  // Default
	}

	// Try to get actual terminal size
	if size := getTerminalSize(); size != nil {
		caps.Width = size.Width
		caps.Height = size.Height
	}

	return caps
}

// detectColorDepth detects the color depth of the terminal
func detectColorDepth() int {
	colorterm := os.Getenv("COLORTERM")
	if colorterm == "truecolor" || colorterm == "24bit" {
		return 24
	}

	term := os.Getenv("TERM")
	if strings.Contains(term, "256color") {
		return 8
	}

	return 4 // Assume 16 colors minimum
}

// TerminalSize represents the size of the terminal
type TerminalSize struct {
	Width  int
	Height int
}

// getTerminalSize gets the current terminal size
func getTerminalSize() *TerminalSize {
	// Try using tput command
	cmd := exec.Command("tput", "cols")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	width := 0
	_, err = fmt.Sscanf(strings.TrimSpace(string(output)), "%d", &width)
	if err != nil {
		return nil
	}

	cmd = exec.Command("tput", "lines")
	output, err = cmd.Output()
	if err != nil {
		return nil
	}

	height := 0
	_, err = fmt.Sscanf(strings.TrimSpace(string(output)), "%d", &height)
	if err != nil {
		return nil
	}

	return &TerminalSize{
		Width:  width,
		Height: height,
	}
}
