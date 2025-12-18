package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/aymanbagabas/go-udiff"
	"github.com/williamcory/agent/sdk/agent"
)

// ApplyCommand handles the apply subcommand
type ApplyCommand struct {
	sessionID string
	dryRun    bool
	reverse   bool
	check     bool
	threeWay  bool
	quiet     bool
}

// NewApplyCommand creates a new apply command with parsed flags
func NewApplyCommand(args []string) (*ApplyCommand, error) {
	cmd := &ApplyCommand{}
	fs := flag.NewFlagSet("apply", flag.ExitOnError)

	fs.StringVar(&cmd.sessionID, "session", "", "Apply diff from specific session (default: latest)")
	fs.BoolVar(&cmd.dryRun, "dry-run", false, "Show what would be applied without changes")
	fs.BoolVar(&cmd.reverse, "reverse", false, "Reverse the diff (unapply changes)")
	fs.BoolVar(&cmd.check, "check", false, "Check if diff applies cleanly")
	fs.BoolVar(&cmd.threeWay, "3way", false, "Use 3-way merge for conflicts")
	fs.BoolVar(&cmd.quiet, "q", false, "Suppress output except errors")
	fs.BoolVar(&cmd.quiet, "quiet", false, "Suppress output except errors")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: agent apply [OPTIONS]\n\n")
		fmt.Fprintf(os.Stderr, "Apply the latest session diff to the working tree.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		return nil, err
	}

	return cmd, nil
}

// Run executes the apply command
func (c *ApplyCommand) Run() error {
	// Get working directory
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get working directory: %w", err)
	}

	// Initialize logger
	logger := agent.NewLoggerFromEnv()
	agent.SetLogger(logger)

	// Determine backend URL
	url := os.Getenv("OPENCODE_SERVER")
	if url == "" {
		url = "http://localhost:8000"
	}

	// Create SDK client
	client := agent.NewClient(url,
		agent.WithDirectory(cwd),
		agent.WithTimeout(30*time.Second),
		agent.WithLogger(logger),
	)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Get session ID (latest or specified)
	sessionID := c.sessionID
	if sessionID == "" {
		sessions, err := client.ListSessions(ctx)
		if err != nil {
			return fmt.Errorf("failed to list sessions: %w", err)
		}
		if len(sessions) == 0 {
			return fmt.Errorf("no sessions found")
		}
		// Most recent session is first
		sessionID = sessions[0].ID
		if !c.quiet {
			fmt.Printf("Using latest session: %s\n", sessionID)
		}
	}

	// Fetch diff from API
	diffs, err := client.GetSessionDiff(ctx, sessionID, nil)
	if err != nil {
		return fmt.Errorf("failed to fetch diff: %w", err)
	}

	if len(diffs) == 0 {
		if !c.quiet {
			fmt.Println("No changes to apply")
		}
		return nil
	}

	// Convert FileDiff to unified diff format
	unifiedDiff := convertToUnifiedDiff(diffs)

	if !c.quiet && c.dryRun {
		fmt.Printf("Dry run - would apply changes to %d file(s):\n", len(diffs))
		for _, d := range diffs {
			fmt.Printf("  %s (+%d -%d)\n", d.File, d.Additions, d.Deletions)
		}
		fmt.Println()
	}

	// Build git apply args
	gitArgs := []string{"apply"}
	if c.dryRun {
		gitArgs = append(gitArgs, "--dry-run")
	}
	if c.reverse {
		gitArgs = append(gitArgs, "--reverse")
	}
	if c.check {
		gitArgs = append(gitArgs, "--check")
	}
	if c.threeWay {
		gitArgs = append(gitArgs, "--3way")
	}
	// Add stdin flag to read from stdin
	gitArgs = append(gitArgs, "-")

	// Run git apply with diff on stdin
	gitCmd := exec.Command("git", gitArgs...)
	gitCmd.Stdin = strings.NewReader(unifiedDiff)
	gitCmd.Dir = cwd

	// Capture output
	output, err := gitCmd.CombinedOutput()

	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			// Print git apply output for debugging
			if len(output) > 0 && !c.quiet {
				fmt.Fprintf(os.Stderr, "%s\n", output)
			}
			return fmt.Errorf("git apply failed with exit code %d", exitErr.ExitCode())
		}
		return fmt.Errorf("git apply failed: %w", err)
	}

	// Print output if not quiet
	if len(output) > 0 && !c.quiet {
		fmt.Print(string(output))
	}

	// Success message
	if !c.dryRun && !c.check && !c.quiet {
		fmt.Println("✓ Changes applied successfully")

		// Print summary
		totalAdditions := 0
		totalDeletions := 0
		for _, d := range diffs {
			totalAdditions += d.Additions
			totalDeletions += d.Deletions
		}
		fmt.Printf("  %d file(s) changed, %d insertion(s)(+), %d deletion(s)(-)\n",
			len(diffs), totalAdditions, totalDeletions)
	} else if c.check && !c.quiet {
		fmt.Println("✓ Diff applies cleanly")
	}

	return nil
}

// convertToUnifiedDiff converts FileDiff objects to unified diff format
// that can be consumed by git apply
func convertToUnifiedDiff(diffs []agent.FileDiff) string {
	var sb strings.Builder

	for _, d := range diffs {
		// Write unified diff header
		sb.WriteString(fmt.Sprintf("diff --git a/%s b/%s\n", d.File, d.File))

		// Determine the operation type
		beforeEmpty := d.Before == ""
		afterEmpty := d.After == ""

		if beforeEmpty && !afterEmpty {
			// New file
			sb.WriteString("new file mode 100644\n")
			sb.WriteString("index 0000000..0000000\n")
			sb.WriteString("--- /dev/null\n")
			sb.WriteString(fmt.Sprintf("+++ b/%s\n", d.File))
		} else if !beforeEmpty && afterEmpty {
			// Deleted file
			sb.WriteString("deleted file mode 100644\n")
			sb.WriteString("index 0000000..0000000\n")
			sb.WriteString(fmt.Sprintf("--- a/%s\n", d.File))
			sb.WriteString("+++ /dev/null\n")
		} else {
			// Modified file
			sb.WriteString("index 0000000..0000000\n")
			sb.WriteString(fmt.Sprintf("--- a/%s\n", d.File))
			sb.WriteString(fmt.Sprintf("+++ b/%s\n", d.File))
		}

		// Generate the unified diff body
		// This is a simple implementation - for production you'd want to use
		// a proper diff algorithm, but this should work for most cases
		sb.WriteString(generateUnifiedDiffBody(d.Before, d.After))
	}

	return sb.String()
}

// generateUnifiedDiffBody generates the actual diff hunks using go-udiff
func generateUnifiedDiffBody(before, after string) string {
	// Use go-udiff to generate proper unified diff with context lines
	// The labels don't matter here since we're only using the body
	diff := udiff.Unified("a", "b", before, after)

	// If the diff is empty (files are identical), return empty string
	if diff == "" {
		return ""
	}

	// Extract just the hunk body (everything after the file headers)
	// The diff includes "--- a\n+++ b\n" which we don't want since
	// convertToUnifiedDiff already adds the proper headers
	lines := strings.Split(diff, "\n")
	var bodyStart int
	for i, line := range lines {
		if strings.HasPrefix(line, "@@") {
			bodyStart = i
			break
		}
	}

	// Join from the first @@ line onwards
	if bodyStart > 0 {
		return strings.Join(lines[bodyStart:], "\n")
	}

	// If no hunk found, return the diff as-is
	// This can happen with empty files
	return diff
}
