package git

import (
	"strconv"
	"strings"
)

// parsePorcelainStatus parses git status --porcelain=v1 output
// Format: XY PATH (where X is staged status, Y is unstaged status)
// Status codes:
// ' ' = unmodified
// M = modified
// A = added
// D = deleted
// R = renamed
// C = copied
// U = updated but unmerged
// ? = untracked
// ! = ignored
func parsePorcelainStatus(output string) []FileChange {
	if output == "" {
		return []FileChange{}
	}

	// Split by null character (we used -z flag)
	lines := strings.Split(output, "\x00")
	changes := make([]FileChange, 0)

	for i := 0; i < len(lines); i++ {
		line := lines[i]
		if len(line) < 3 {
			continue
		}

		// Get status codes (first two characters)
		stagedCode := line[0]
		unstagedCode := line[1]
		path := strings.TrimSpace(line[3:])

		if path == "" {
			continue
		}

		// Handle renamed/copied files (next line contains old path)
		var oldPath string
		if stagedCode == 'R' || stagedCode == 'C' {
			if i+1 < len(lines) {
				oldPath = lines[i+1]
				i++ // Skip the next line
			}
		}

		// Parse staged status
		if stagedCode != ' ' && stagedCode != '?' {
			change := FileChange{
				Path:    path,
				OldPath: oldPath,
				Staged:  true,
			}
			change.Status = parseStatusCode(stagedCode)
			changes = append(changes, change)
		}

		// Parse unstaged status
		if unstagedCode != ' ' {
			change := FileChange{
				Path:   path,
				Staged: false,
			}
			if unstagedCode == '?' {
				change.Status = StatusUntracked
			} else {
				change.Status = parseStatusCode(unstagedCode)
			}
			changes = append(changes, change)
		}
	}

	return changes
}

// parseStatusCode converts a git status code to ChangeStatus
func parseStatusCode(code byte) ChangeStatus {
	switch code {
	case 'M':
		return StatusModified
	case 'A':
		return StatusAdded
	case 'D':
		return StatusDeleted
	case 'R':
		return StatusRenamed
	case 'C':
		return StatusCopied
	case '?':
		return StatusUntracked
	case 'U':
		// Unmerged (conflict)
		return StatusModified // Treat as modified for now
	default:
		return StatusUnmodified
	}
}

// parseBranchInfo parses git branch -vv output
// Example: "* main 1234567 [origin/main: ahead 2, behind 1] commit message"
func parseBranchInfo(output string) (string, int, int) {
	lines := strings.Split(output, "\n")
	var branch string
	var ahead, behind int

	for _, line := range lines {
		// Look for the current branch (marked with *)
		if !strings.HasPrefix(line, "*") {
			continue
		}

		// Parse branch name
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		branch = parts[1]

		// Parse tracking info
		// Look for [origin/main: ahead 2, behind 1] pattern
		bracketStart := strings.Index(line, "[")
		bracketEnd := strings.Index(line, "]")
		if bracketStart == -1 || bracketEnd == -1 {
			break
		}

		trackingInfo := line[bracketStart+1 : bracketEnd]

		// Parse ahead/behind counts
		if strings.Contains(trackingInfo, "ahead") {
			aheadIdx := strings.Index(trackingInfo, "ahead")
			aheadPart := trackingInfo[aheadIdx:]
			aheadFields := strings.Fields(aheadPart)
			if len(aheadFields) >= 2 {
				if val, err := strconv.Atoi(strings.TrimRight(aheadFields[1], ",")); err == nil {
					ahead = val
				}
			}
		}

		if strings.Contains(trackingInfo, "behind") {
			behindIdx := strings.Index(trackingInfo, "behind")
			behindPart := trackingInfo[behindIdx:]
			behindFields := strings.Fields(behindPart)
			if len(behindFields) >= 2 {
				if val, err := strconv.Atoi(strings.TrimRight(behindFields[1], ",")); err == nil {
					behind = val
				}
			}
		}

		break
	}

	return branch, ahead, behind
}

// parseDiffStats parses git diff --numstat output
// Format: "insertions\tdeletions\tfilename"
func parseDiffStats(output string) (int, int) {
	if output == "" {
		return 0, 0
	}

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) == 0 {
		return 0, 0
	}

	// Take the first line (should only be one file)
	fields := strings.Fields(lines[0])
	if len(fields) < 2 {
		return 0, 0
	}

	var insertions, deletions int

	// Handle binary files (marked with -)
	if fields[0] != "-" {
		if val, err := strconv.Atoi(fields[0]); err == nil {
			insertions = val
		}
	}

	if fields[1] != "-" {
		if val, err := strconv.Atoi(fields[1]); err == nil {
			deletions = val
		}
	}

	return insertions, deletions
}

// FormatFileStatus returns a display string for a file status
func FormatFileStatus(status ChangeStatus) string {
	switch status {
	case StatusAdded:
		return "+"
	case StatusModified:
		return "M"
	case StatusDeleted:
		return "D"
	case StatusRenamed:
		return "R"
	case StatusCopied:
		return "C"
	case StatusUntracked:
		return "?"
	default:
		return " "
	}
}
