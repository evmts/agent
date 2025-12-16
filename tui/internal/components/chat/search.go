package chat

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
)

// SearchState represents the current search state
type SearchState struct {
	Active        bool
	Query         string
	Matches       []SearchMatch
	CurrentIndex  int
	CaseSensitive bool
	UseRegex      bool
}

// SearchMatch represents a single search match
type SearchMatch struct {
	MessageIndex int
	PartIndex    int
	StartPos     int
	EndPos       int
	Preview      string
}

// NewSearchState creates a new empty search state
func NewSearchState() SearchState {
	return SearchState{
		Active:        false,
		Query:         "",
		Matches:       []SearchMatch{},
		CurrentIndex:  -1,
		CaseSensitive: false,
		UseRegex:      false,
	}
}

// ActivateSearch activates the search mode
func (s *SearchState) ActivateSearch() {
	s.Active = true
	s.Query = ""
	s.Matches = []SearchMatch{}
	s.CurrentIndex = -1
}

// DeactivateSearch deactivates the search mode
func (s *SearchState) DeactivateSearch() {
	s.Active = false
	s.Query = ""
	s.Matches = []SearchMatch{}
	s.CurrentIndex = -1
}

// SetQuery updates the search query and triggers a new search
func (s *SearchState) SetQuery(query string) {
	s.Query = query
}

// NextMatch moves to the next match
func (s *SearchState) NextMatch() {
	if len(s.Matches) == 0 {
		return
	}
	s.CurrentIndex = (s.CurrentIndex + 1) % len(s.Matches)
}

// PrevMatch moves to the previous match
func (s *SearchState) PrevMatch() {
	if len(s.Matches) == 0 {
		return
	}
	s.CurrentIndex--
	if s.CurrentIndex < 0 {
		s.CurrentIndex = len(s.Matches) - 1
	}
}

// HasMatches returns true if there are any matches
func (s SearchState) HasMatches() bool {
	return len(s.Matches) > 0
}

// GetCurrentMatch returns the current match if available
func (s SearchState) GetCurrentMatch() *SearchMatch {
	if s.CurrentIndex >= 0 && s.CurrentIndex < len(s.Matches) {
		return &s.Matches[s.CurrentIndex]
	}
	return nil
}

// PerformSearch searches through all messages and updates matches
func (s *SearchState) PerformSearch(messages []Message) {
	s.Matches = []SearchMatch{}
	s.CurrentIndex = -1

	if s.Query == "" {
		return
	}

	// Prepare query for comparison
	query := s.Query
	if !s.CaseSensitive {
		query = strings.ToLower(query)
	}

	// Search through all messages
	for msgIdx, msg := range messages {
		// Search through all parts
		for partIdx, part := range msg.Parts {
			text := extractSearchableText(part)
			if text == "" {
				continue
			}

			// Find all matches in this text
			searchText := text
			if !s.CaseSensitive {
				searchText = strings.ToLower(text)
			}

			offset := 0
			for {
				idx := strings.Index(searchText[offset:], query)
				if idx == -1 {
					break
				}

				matchStart := offset + idx
				matchEnd := matchStart + len(query)

				// Create preview (50 chars before and after)
				previewStart := matchStart - 50
				if previewStart < 0 {
					previewStart = 0
				}
				previewEnd := matchEnd + 50
				if previewEnd > len(text) {
					previewEnd = len(text)
				}

				preview := text[previewStart:previewEnd]
				if previewStart > 0 {
					preview = "..." + preview
				}
				if previewEnd < len(text) {
					preview = preview + "..."
				}

				s.Matches = append(s.Matches, SearchMatch{
					MessageIndex: msgIdx,
					PartIndex:    partIdx,
					StartPos:     matchStart,
					EndPos:       matchEnd,
					Preview:      preview,
				})

				offset = matchEnd
			}
		}
	}

	// Set current index to first match if any
	if len(s.Matches) > 0 {
		s.CurrentIndex = 0
	}
}

// extractSearchableText extracts searchable text from a part
func extractSearchableText(part agent.Part) string {
	var texts []string

	// Add main text content
	if part.IsText() && part.Text != "" {
		texts = append(texts, part.Text)
	}

	// Add reasoning/thinking content
	if part.IsReasoning() && part.Text != "" {
		texts = append(texts, part.Text)
	}

	// Add tool information
	if part.IsTool() && part.State != nil {
		// Add tool name
		texts = append(texts, part.Tool)

		// Add tool output
		if part.State.Output != "" {
			texts = append(texts, part.State.Output)
		}

		// Add tool title
		if part.State.Title != nil && *part.State.Title != "" {
			texts = append(texts, *part.State.Title)
		}
	}

	return strings.Join(texts, " ")
}

// RenderSearchOverlay renders the search input overlay
func RenderSearchOverlay(state SearchState, width int) string {
	theme := styles.GetCurrentTheme()

	// Search icon and input
	searchIcon := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Render("🔍 Search: ")

	queryStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary)

	// Match counter
	matchInfo := ""
	if state.Query != "" {
		if len(state.Matches) > 0 {
			matchStyle := lipgloss.NewStyle().
				Foreground(theme.Success)
			matchInfo = matchStyle.Render(fmt.Sprintf(" %d of %d matches",
				state.CurrentIndex+1, len(state.Matches)))
		} else {
			matchStyle := lipgloss.NewStyle().
				Foreground(theme.Muted)
			matchInfo = matchStyle.Render(" No matches")
		}
	}

	// Navigation hints
	hintStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)
	hints := hintStyle.Render("  [Enter: next] [Shift+Enter: prev] [Esc: close]")

	// Combine elements
	searchLine := searchIcon + queryStyle.Render(state.Query) + matchInfo

	// Container style
	containerStyle := lipgloss.NewStyle().
		Width(width).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(0, 1).
		Background(theme.Background)

	content := searchLine + "\n" + hints
	return containerStyle.Render(content)
}

// HighlightMatches highlights search matches in text
func HighlightMatches(text string, query string, isCurrentMatch bool) string {
	if query == "" {
		return text
	}

	theme := styles.GetCurrentTheme()

	// Style for matches
	var highlightStyle lipgloss.Style
	if isCurrentMatch {
		// Current match - more prominent
		highlightStyle = lipgloss.NewStyle().
			Background(theme.Warning).
			Foreground(theme.Background).
			Bold(true)
	} else {
		// Other matches - less prominent
		highlightStyle = lipgloss.NewStyle().
			Background(theme.Warning).
			Foreground(theme.Background)
	}

	// Case-insensitive search
	lowerText := strings.ToLower(text)
	lowerQuery := strings.ToLower(query)

	var result strings.Builder
	lastEnd := 0

	for {
		idx := strings.Index(lowerText[lastEnd:], lowerQuery)
		if idx == -1 {
			result.WriteString(text[lastEnd:])
			break
		}

		matchStart := lastEnd + idx
		matchEnd := matchStart + len(query)

		result.WriteString(text[lastEnd:matchStart])
		result.WriteString(highlightStyle.Render(text[matchStart:matchEnd]))
		lastEnd = matchEnd
	}

	return result.String()
}

// GetMatchMessageIndex returns the message index for the current match
func (s SearchState) GetMatchMessageIndex() int {
	match := s.GetCurrentMatch()
	if match != nil {
		return match.MessageIndex
	}
	return -1
}
