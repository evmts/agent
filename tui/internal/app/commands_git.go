package app

import (
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/tui/internal/components/sidebar"
	"github.com/williamcory/agent/tui/internal/components/toast"
	"github.com/williamcory/agent/tui/internal/git"
)

// refreshGitStatus refreshes the git status in the background
func (m Model) refreshGitStatus() tea.Cmd {
	return func() tea.Msg {
		workDir, err := os.Getwd()
		if err != nil {
			return sidebar.GitStatusUpdatedMsg{Status: &git.GitStatus{IsRepo: false}}
		}

		status, err := git.GetStatus(workDir)
		if err != nil {
			return sidebar.GitStatusUpdatedMsg{Status: &git.GitStatus{IsRepo: false}}
		}

		return sidebar.GitStatusUpdatedMsg{Status: status}
	}
}

// handleGitStageToggle handles staging/unstaging a file
func (m Model) handleGitStageToggle(msg sidebar.GitStageToggleMsg) tea.Cmd {
	return func() tea.Msg {
		workDir, err := os.Getwd()
		if err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to get working directory: %w", err)}
		}

		status := m.sidebar.GetGitStatus()
		if status == nil {
			return gitErrorMsg{err: fmt.Errorf("no git status available")}
		}

		// Determine which file to stage/unstage
		var filePath string
		var shouldStage bool

		switch msg.ViewMode {
		case sidebar.GitViewStaged:
			// Unstage the file
			if msg.Index < len(status.Staged) {
				filePath = status.Staged[msg.Index].Path
				shouldStage = false
			}
		case sidebar.GitViewUnstaged:
			// Stage the file
			offset := len(status.Staged)
			idx := msg.Index - offset
			if idx >= 0 && idx < len(status.Unstaged) {
				filePath = status.Unstaged[idx].Path
				shouldStage = true
			}
		case sidebar.GitViewUntracked:
			// Stage the file
			offset := len(status.Staged) + len(status.Unstaged)
			idx := msg.Index - offset
			if idx >= 0 && idx < len(status.Untracked) {
				filePath = status.Untracked[idx]
				shouldStage = true
			}
		}

		if filePath == "" {
			return gitErrorMsg{err: fmt.Errorf("invalid file selection")}
		}

		var cmdErr error
		if shouldStage {
			cmdErr = git.StageFile(workDir, filePath)
		} else {
			cmdErr = git.UnstageFile(workDir, filePath)
		}

		if cmdErr != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to stage/unstage file: %w", cmdErr)}
		}

		// Refresh git status after staging/unstaging
		return sidebar.GitRefreshMsg{}
	}
}

// handleGitStageAll handles staging all files
func (m Model) handleGitStageAll() tea.Cmd {
	return func() tea.Msg {
		workDir, err := os.Getwd()
		if err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to get working directory: %w", err)}
		}

		if err := git.StageAll(workDir); err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to stage all files: %w", err)}
		}

		// Refresh git status after staging
		return sidebar.GitRefreshMsg{}
	}
}

// handleGitDiff handles viewing diff for a file
func (m Model) handleGitDiff(msg sidebar.GitDiffMsg) tea.Cmd {
	return func() tea.Msg {
		workDir, err := os.Getwd()
		if err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to get working directory: %w", err)}
		}

		status := m.sidebar.GetGitStatus()
		if status == nil {
			return gitErrorMsg{err: fmt.Errorf("no git status available")}
		}

		// Determine which file to diff
		var filePath string
		var staged bool

		switch msg.ViewMode {
		case sidebar.GitViewStaged:
			if msg.Index < len(status.Staged) {
				filePath = status.Staged[msg.Index].Path
				staged = true
			}
		case sidebar.GitViewUnstaged:
			offset := len(status.Staged)
			idx := msg.Index - offset
			if idx >= 0 && idx < len(status.Unstaged) {
				filePath = status.Unstaged[idx].Path
				staged = false
			}
		case sidebar.GitViewUntracked:
			// Untracked files don't have diffs
			return gitErrorMsg{err: fmt.Errorf("cannot view diff for untracked files")}
		}

		if filePath == "" {
			return gitErrorMsg{err: fmt.Errorf("invalid file selection")}
		}

		diff, err := git.GetFileDiff(workDir, filePath, staged)
		if err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to get diff: %w", err)}
		}

		return gitDiffViewMsg{file: filePath, diff: diff}
	}
}

// handleGitCommit handles creating a commit
func (m Model) handleGitCommit() tea.Cmd {
	// This would show a dialog to get commit message
	// For now, we'll return a message to show the commit dialog
	return func() tea.Msg {
		return gitCommitDialogMsg{}
	}
}

// Git-related messages

// gitErrorMsg represents a git operation error
type gitErrorMsg struct {
	err error
}

// gitDiffViewMsg represents a request to view a diff
type gitDiffViewMsg struct {
	file string
	diff string
}

// gitCommitDialogMsg represents a request to show the commit dialog
type gitCommitDialogMsg struct{}

// gitCommitMsg represents a git commit operation
type gitCommitMsg struct {
	message string
}

// executeGitCommit executes a git commit with the given message
func (m Model) executeGitCommit(message string) tea.Cmd {
	return func() tea.Msg {
		workDir, err := os.Getwd()
		if err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to get working directory: %w", err)}
		}

		if err := git.CreateCommit(workDir, message); err != nil {
			return gitErrorMsg{err: fmt.Errorf("failed to create commit: %w", err)}
		}

		return gitCommitSuccessMsg{message: message}
	}
}

// gitCommitSuccessMsg represents a successful commit
type gitCommitSuccessMsg struct {
	message string
}

// showGitToast shows a toast notification for git operations
func (m *Model) showGitToast(message string, toastType toast.ToastType) tea.Cmd {
	return m.toast.Add(message, toastType, 3*time.Second)
}
