package app

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/tui/internal/clipboard"
	"github.com/williamcory/agent/tui/internal/components/toast"
)

// executeShellCommand executes a shell command and returns the result
func (m Model) executeShellCommand(cmdStr string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		cmd := exec.CommandContext(ctx, "bash", "-c", cmdStr)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		err := cmd.Run()

		output := stdout.String()
		if stderr.Len() > 0 {
			if output != "" {
				output += "\n"
			}
			output += stderr.String()
		}

		return shellCommandResultMsg{output: output, err: err}
	}
}

// openExternalEditor opens an external editor with the given content
func (m Model) openExternalEditor(initialContent string) tea.Cmd {
	return tea.ExecProcess(getEditorCmd(initialContent), func(err error) tea.Msg {
		if err != nil {
			return editorResultMsg{err: err}
		}
		// Read the temp file after editor closes
		content, readErr := readTempFile()
		return editorResultMsg{content: content, err: readErr}
	})
}

// getEditorCmd returns the command to open the external editor
func getEditorCmd(content string) *exec.Cmd {
	// Get editor from environment
	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = os.Getenv("VISUAL")
	}
	if editor == "" {
		// Fallback to common editors
		if _, err := exec.LookPath("nvim"); err == nil {
			editor = "nvim"
		} else if _, err := exec.LookPath("vim"); err == nil {
			editor = "vim"
		} else if _, err := exec.LookPath("nano"); err == nil {
			editor = "nano"
		} else {
			editor = "vi"
		}
	}

	// Create temp file with content
	tmpFile, err := os.CreateTemp("", "claude-input-*.txt")
	if err != nil {
		return exec.Command("echo", "Failed to create temp file")
	}
	defer tmpFile.Close()

	// Write initial content
	if content != "" {
		tmpFile.WriteString(content)
	}

	// Store temp file path in environment for later reading
	os.Setenv("CLAUDE_TEMP_FILE", tmpFile.Name())

	return exec.Command(editor, tmpFile.Name())
}

// readTempFile reads the content from the temp file
func readTempFile() (string, error) {
	tempPath := os.Getenv("CLAUDE_TEMP_FILE")
	if tempPath == "" {
		return "", fmt.Errorf("no temp file path")
	}

	content, err := os.ReadFile(tempPath)
	if err != nil {
		return "", err
	}

	// Clean up temp file
	os.Remove(tempPath)
	os.Unsetenv("CLAUDE_TEMP_FILE")

	return strings.TrimSpace(string(content)), nil
}

// copyCodeBlock copies code block content to clipboard
func (m Model) copyCodeBlock(content string) tea.Cmd {
	return func() tea.Msg {
		err := clipboard.Copy(content)
		if err != nil {
			return m.ShowToast("Failed to copy: "+err.Error(), toast.ToastError, 3*time.Second)()
		}
		return m.ShowToast("Copied to clipboard!", toast.ToastSuccess, 2*time.Second)()
	}
}
