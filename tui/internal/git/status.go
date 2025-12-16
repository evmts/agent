package git

import (
	"context"
	"os/exec"
	"strings"
	"time"
)

const (
	// DEFAULT_GIT_TIMEOUT is the default timeout for git commands
	DEFAULT_GIT_TIMEOUT = 5 * time.Second
)

// ChangeStatus represents the status of a file change
type ChangeStatus string

const (
	StatusAdded      ChangeStatus = "added"
	StatusModified   ChangeStatus = "modified"
	StatusDeleted    ChangeStatus = "deleted"
	StatusRenamed    ChangeStatus = "renamed"
	StatusCopied     ChangeStatus = "copied"
	StatusUntracked  ChangeStatus = "untracked"
	StatusUnmodified ChangeStatus = "unmodified"
)

// FileChange represents a file that has changed
type FileChange struct {
	Path       string       // File path
	Status     ChangeStatus // Change status
	OldPath    string       // For renames (optional)
	Insertions int          // Number of insertions
	Deletions  int          // Number of deletions
	Staged     bool         // Whether the change is staged
}

// GitStatus represents the current git repository status
type GitStatus struct {
	Branch       string       // Current branch name
	Ahead        int          // Commits ahead of upstream
	Behind       int          // Commits behind upstream
	Staged       []FileChange // Staged changes
	Unstaged     []FileChange // Unstaged changes
	Untracked    []string     // Untracked files
	IsRepo       bool         // Whether we're in a git repository
	HasConflicts bool         // Whether there are merge conflicts
}

// GetStatus retrieves the current git status
func GetStatus(workDir string) (*GitStatus, error) {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	// First, check if we're in a git repository
	if !isGitRepo(ctx, workDir) {
		return &GitStatus{IsRepo: false}, nil
	}

	status := &GitStatus{
		IsRepo:    true,
		Staged:    make([]FileChange, 0),
		Unstaged:  make([]FileChange, 0),
		Untracked: make([]string, 0),
	}

	// Get branch information
	branch, ahead, behind, err := getBranchInfo(ctx, workDir)
	if err == nil {
		status.Branch = branch
		status.Ahead = ahead
		status.Behind = behind
	}

	// Get file changes using porcelain format
	changes, err := getFileChanges(ctx, workDir)
	if err != nil {
		return status, err
	}

	// Separate staged, unstaged, and untracked files
	for _, change := range changes {
		if change.Status == StatusUntracked {
			status.Untracked = append(status.Untracked, change.Path)
		} else if change.Staged {
			status.Staged = append(status.Staged, change)
		} else {
			status.Unstaged = append(status.Unstaged, change)
		}
	}

	// Check for merge conflicts
	status.HasConflicts = hasConflicts(changes)

	return status, nil
}

// isGitRepo checks if the working directory is a git repository
func isGitRepo(ctx context.Context, workDir string) bool {
	cmd := exec.CommandContext(ctx, "git", "rev-parse", "--git-dir")
	cmd.Dir = workDir
	err := cmd.Run()
	return err == nil
}

// getBranchInfo retrieves the current branch name and tracking information
func getBranchInfo(ctx context.Context, workDir string) (string, int, int, error) {
	cmd := exec.CommandContext(ctx, "git", "branch", "-vv")
	cmd.Dir = workDir
	output, err := cmd.Output()
	if err != nil {
		return "", 0, 0, err
	}

	// Parse the branch info
	branch, ahead, behind := parseBranchInfo(string(output))
	return branch, ahead, behind, nil
}

// getFileChanges retrieves file changes using git status --porcelain
func getFileChanges(ctx context.Context, workDir string) ([]FileChange, error) {
	cmd := exec.CommandContext(ctx, "git", "status", "--porcelain=v1", "-z")
	cmd.Dir = workDir
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	// Parse the porcelain output
	changes := parsePorcelainStatus(string(output))

	// Get diff stats for staged and unstaged files
	for i := range changes {
		if changes[i].Status != StatusUntracked {
			insertions, deletions := getDiffStats(ctx, workDir, changes[i].Path, changes[i].Staged)
			changes[i].Insertions = insertions
			changes[i].Deletions = deletions
		}
	}

	return changes, nil
}

// getDiffStats gets insertion/deletion counts for a file
func getDiffStats(ctx context.Context, workDir, path string, staged bool) (int, int) {
	var cmd *exec.Cmd
	if staged {
		// Diff between index and HEAD
		cmd = exec.CommandContext(ctx, "git", "diff", "--cached", "--numstat", "--", path)
	} else {
		// Diff between working tree and index
		cmd = exec.CommandContext(ctx, "git", "diff", "--numstat", "--", path)
	}
	cmd.Dir = workDir
	output, err := cmd.Output()
	if err != nil {
		return 0, 0
	}

	return parseDiffStats(string(output))
}

// hasConflicts checks if there are any merge conflicts
func hasConflicts(changes []FileChange) bool {
	for _, change := range changes {
		// In porcelain format, conflicts are marked with special status codes
		// This will be handled in the parser
		if strings.Contains(string(change.Status), "conflict") {
			return true
		}
	}
	return false
}

// StageFile stages a file for commit
func StageFile(workDir, path string) error {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	cmd := exec.CommandContext(ctx, "git", "add", "--", path)
	cmd.Dir = workDir
	return cmd.Run()
}

// UnstageFile unstages a file
func UnstageFile(workDir, path string) error {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	cmd := exec.CommandContext(ctx, "git", "reset", "HEAD", "--", path)
	cmd.Dir = workDir
	return cmd.Run()
}

// StageAll stages all changes
func StageAll(workDir string) error {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	cmd := exec.CommandContext(ctx, "git", "add", "-A")
	cmd.Dir = workDir
	return cmd.Run()
}

// GetFileDiff gets the diff for a specific file
func GetFileDiff(workDir, path string, staged bool) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	var cmd *exec.Cmd
	if staged {
		cmd = exec.CommandContext(ctx, "git", "diff", "--cached", "--", path)
	} else {
		cmd = exec.CommandContext(ctx, "git", "diff", "--", path)
	}
	cmd.Dir = workDir
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	return string(output), nil
}

// CreateCommit creates a commit with the given message
func CreateCommit(workDir, message string) error {
	ctx, cancel := context.WithTimeout(context.Background(), DEFAULT_GIT_TIMEOUT)
	defer cancel()

	cmd := exec.CommandContext(ctx, "git", "commit", "-m", message)
	cmd.Dir = workDir
	return cmd.Run()
}
