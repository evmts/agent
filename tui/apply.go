package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

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

// generateUnifiedDiffBody generates the actual diff hunks
// This is a simplified implementation
func generateUnifiedDiffBody(before, after string) string {
	beforeLines := strings.Split(before, "\n")
	afterLines := strings.Split(after, "\n")

	// Simple implementation: if empty before, all additions; if empty after, all deletions
	if before == "" && after != "" {
		// All new lines
		var sb strings.Builder
		sb.WriteString(fmt.Sprintf("@@ -0,0 +1,%d @@\n", len(afterLines)))
		for _, line := range afterLines {
			sb.WriteString("+")
			sb.WriteString(line)
			sb.WriteString("\n")
		}
		return sb.String()
	}

	if after == "" && before != "" {
		// All deleted lines
		var sb strings.Builder
		sb.WriteString(fmt.Sprintf("@@ -1,%d +0,0 @@\n", len(beforeLines)))
		for _, line := range beforeLines {
			sb.WriteString("-")
			sb.WriteString(line)
			sb.WriteString("\n")
		}
		return sb.String()
	}

	// For modifications, use a simple approach:
	// Delete all old lines, add all new lines
	// A proper diff algorithm would be better, but this works
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("@@ -1,%d +1,%d @@\n", len(beforeLines), len(afterLines)))

	// Remove old lines
	for _, line := range beforeLines {
		sb.WriteString("-")
		sb.WriteString(line)
		sb.WriteString("\n")
	}

	// Add new lines
	for _, line := range afterLines {
		sb.WriteString("+")
		sb.WriteString(line)
		sb.WriteString("\n")
	}

	return sb.String()
}
