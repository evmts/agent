package embedded

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

//go:embed bin/*
var serverBinary embed.FS

// ExtractServer extracts the embedded Python server binary to a temporary location.
// Returns the path to the extracted binary.
func ExtractServer() (string, error) {
	// Determine the correct binary name based on OS
	binaryName := "agent-server"
	if runtime.GOOS == "windows" {
		binaryName = "agent-server.exe"
	}

	// Create a unique temp directory for this instance
	tmpDir, err := os.MkdirTemp("", "agent-server-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temp directory: %w", err)
	}

	// Extract the binary
	srcPath := filepath.Join("bin", binaryName)
	data, err := serverBinary.ReadFile(srcPath)
	if err != nil {
		os.RemoveAll(tmpDir)
		return "", fmt.Errorf("failed to read embedded binary: %w", err)
	}

	destPath := filepath.Join(tmpDir, binaryName)
	if err := os.WriteFile(destPath, data, 0755); err != nil {
		os.RemoveAll(tmpDir)
		return "", fmt.Errorf("failed to write binary: %w", err)
	}

	return destPath, nil
}

// CleanupServer removes the extracted server binary and its directory.
func CleanupServer(path string) error {
	if path == "" {
		return nil
	}
	return os.RemoveAll(filepath.Dir(path))
}
