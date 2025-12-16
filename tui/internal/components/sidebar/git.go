package sidebar

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"tui/internal/git"
	"tui/internal/styles"
)

const (
	// MAX_FILE_DISPLAY_LENGTH is the maximum length for file paths in the git tab
	MAX_FILE_DISPLAY_LENGTH = 30
	// MAX_VISIBLE_FILES is the maximum number of files to show per section
	MAX_VISIBLE_FILES = 8
)

// gitStatusStyle returns a style for git status indicators
func gitStatusStyle(status git.ChangeStatus) lipgloss.Style {
	theme := styles.GetCurrentTheme()
	switch status {
	case git.StatusAdded:
		return lipgloss.NewStyle().Foreground(theme.Success)
	case git.StatusModified:
		return lipgloss.NewStyle().Foreground(theme.Warning)
	case git.StatusDeleted:
		return lipgloss.NewStyle().Foreground(theme.Error)
	case git.StatusRenamed:
		return lipgloss.NewStyle().Foreground(theme.Primary)
	case git.StatusUntracked:
		return lipgloss.NewStyle().Foreground(theme.Muted)
	default:
		return lipgloss.NewStyle().Foreground(theme.TextSecondary)
	}
}

// branchStyle returns a style for the branch name
func branchStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Primary).
		Bold(true)
}

// trackingStyle returns a style for tracking info
func trackingStyle(ahead, behind int) lipgloss.Style {
	theme := styles.GetCurrentTheme()
	if ahead > 0 || behind > 0 {
		return lipgloss.NewStyle().Foreground(theme.Warning)
	}
	return lipgloss.NewStyle().Foreground(theme.Success)
}

// renderGitTab renders the git status tab content
func renderGitTab(m Model) string {
	var content strings.Builder

	if m.gitStatus == nil || !m.gitStatus.IsRepo {
		content.WriteString(emptyStyle().Render("Not a git repository"))
		return content.String()
	}

	status := m.gitStatus

	// Branch info
	if status.Branch != "" {
		branchLine := branchStyle().Render(status.Branch)

		// Add tracking info
		if status.Ahead > 0 || status.Behind > 0 {
			tracking := ""
			if status.Ahead > 0 {
				tracking += fmt.Sprintf("↑%d", status.Ahead)
			}
			if status.Behind > 0 {
				if tracking != "" {
					tracking += " "
				}
				tracking += fmt.Sprintf("↓%d", status.Behind)
			}
			branchLine += " " + trackingStyle(status.Ahead, status.Behind).Render(tracking)
		}

		content.WriteString(branchLine)
		content.WriteString("\n")
		content.WriteString(sectionLabelStyle().Render(strings.Repeat("─", 35)))
		content.WriteString("\n\n")
	}

	// Staged files
	if len(status.Staged) > 0 {
		content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("Staged (%d)", len(status.Staged))))
		content.WriteString("\n")
		content.WriteString(renderFileList(status.Staged, m.selectedGitIndex, 0, m.gitViewMode == GitViewStaged))
		content.WriteString("\n")
	}

	// Unstaged changes
	if len(status.Unstaged) > 0 {
		stagedOffset := len(status.Staged)
		content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("Changes (%d)", len(status.Unstaged))))
		content.WriteString("\n")
		content.WriteString(renderFileList(status.Unstaged, m.selectedGitIndex, stagedOffset, m.gitViewMode == GitViewUnstaged))
		content.WriteString("\n")
	}

	// Untracked files
	if len(status.Untracked) > 0 {
		untrackedOffset := len(status.Staged) + len(status.Unstaged)
		content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("Untracked (%d)", len(status.Untracked))))
		content.WriteString("\n")
		content.WriteString(renderUntrackedList(status.Untracked, m.selectedGitIndex, untrackedOffset, m.gitViewMode == GitViewUntracked))
		content.WriteString("\n")
	}

	// Show conflicts warning if any
	if status.HasConflicts {
		warning := lipgloss.NewStyle().
			Foreground(styles.GetCurrentTheme().Error).
			Bold(true).
			Render("⚠ Merge conflicts detected")
		content.WriteString(warning)
		content.WriteString("\n\n")
	}

	// Help text for git actions
	if len(status.Staged)+len(status.Unstaged)+len(status.Untracked) > 0 {
		content.WriteString(sectionLabelStyle().Render(strings.Repeat("─", 35)))
		content.WriteString("\n")
		helpStyle := lipgloss.NewStyle().Foreground(styles.GetCurrentTheme().Muted)
		content.WriteString(helpStyle.Render("[a] Stage all  [c] Commit"))
		content.WriteString("\n")
		content.WriteString(helpStyle.Render("[d] Diff       [r] Refresh"))
	}

	return content.String()
}

// renderFileList renders a list of file changes
func renderFileList(files []git.FileChange, selectedIndex, offset int, isActiveSection bool) string {
	var content strings.Builder
	theme := styles.GetCurrentTheme()

	maxFiles := MAX_VISIBLE_FILES
	displayCount := len(files)
	if displayCount > maxFiles {
		displayCount = maxFiles
	}

	for i := 0; i < displayCount; i++ {
		file := files[i]
		statusCode := git.FormatFileStatus(file.Status)
		statusStyled := gitStatusStyle(file.Status).Render(statusCode)

		// Truncate file path if too long
		path := file.Path
		if len(path) > MAX_FILE_DISPLAY_LENGTH {
			path = "..." + path[len(path)-MAX_FILE_DISPLAY_LENGTH+3:]
		}

		// Format stats
		stats := ""
		if file.Insertions > 0 || file.Deletions > 0 {
			if file.Insertions > 0 {
				stats += diffAddedStyle().Render(fmt.Sprintf("+%d", file.Insertions))
			}
			if file.Deletions > 0 {
				if stats != "" {
					stats += " "
				}
				stats += diffRemovedStyle().Render(fmt.Sprintf("-%d", file.Deletions))
			}
		}

		// Build the line
		fileLine := fmt.Sprintf("  %s %s", statusStyled, path)
		if stats != "" {
			fileLine += " " + stats
		}

		// Highlight if selected
		globalIndex := offset + i
		if isActiveSection && selectedIndex == globalIndex {
			style := lipgloss.NewStyle().
				Background(theme.Primary).
				Foreground(theme.Background).
				Bold(true)
			fileLine = style.Render("▶ " + statusStyled + " " + path)
			if stats != "" {
				fileLine += " " + stats
			}
		}

		content.WriteString(fileLine)
		content.WriteString("\n")
	}

	// Show "and X more" if there are more files
	if len(files) > maxFiles {
		remaining := len(files) - maxFiles
		content.WriteString(sectionLabelStyle().Render(fmt.Sprintf("  ... and %d more", remaining)))
		content.WriteString("\n")
	}

	return content.String()
}

// renderUntrackedList renders a list of untracked files
func renderUntrackedList(files []string, selectedIndex, offset int, isActiveSection bool) string {
	var content strings.Builder
	theme := styles.GetCurrentTheme()

	maxFiles := MAX_VISIBLE_FILES
	displayCount := len(files)
	if displayCount > maxFiles {
		displayCount = maxFiles
	}

	for i := 0; i < displayCount; i++ {
		path := files[i]

		// Truncate file path if too long
		if len(path) > MAX_FILE_DISPLAY_LENGTH {
			path = "..." + path[len(path)-MAX_FILE_DISPLAY_LENGTH+3:]
		}

		statusStyled := gitStatusStyle(git.StatusUntracked).Render("?")
		fileLine := fmt.Sprintf("  %s %s", statusStyled, path)

		// Highlight if selected
		globalIndex := offset + i
		if isActiveSection && selectedIndex == globalIndex {
			style := lipgloss.NewStyle().
				Background(theme.Primary).
				Foreground(theme.Background).
				Bold(true)
			fileLine = style.Render("▶ " + statusStyled + " " + path)
		}

		content.WriteString(fileLine)
		content.WriteString("\n")
	}

	// Show "and X more" if there are more files
	if len(files) > maxFiles {
		remaining := len(files) - maxFiles
		content.WriteString(sectionLabelStyle().Render(fmt.Sprintf("  ... and %d more", remaining)))
		content.WriteString("\n")
	}

	return content.String()
}

// formatGitBranchInfo formats the branch info for display
func formatGitBranchInfo(branch string, ahead, behind int) string {
	if branch == "" {
		return "No branch"
	}

	info := branch
	if ahead > 0 || behind > 0 {
		info += " ("
		if ahead > 0 {
			info += fmt.Sprintf("↑%d", ahead)
		}
		if behind > 0 {
			if ahead > 0 {
				info += " "
			}
			info += fmt.Sprintf("↓%d", behind)
		}
		info += ")"
	}

	return info
}
