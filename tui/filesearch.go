package main

import (
	"io/fs"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// FileIndex holds indexed files for quick search
type FileIndex struct {
	files    []string
	lastScan time.Time
	mu       sync.RWMutex
}

// FileMatch represents a file match with its score
type FileMatch struct {
	Path  string
	Score int
}

// isGitRepo checks if the directory is in a git repository
func isGitRepo(root string) bool {
	cmd := exec.Command("git", "rev-parse", "--git-dir")
	cmd.Dir = root
	return cmd.Run() == nil
}

// Scan builds the file index
func (idx *FileIndex) Scan(root string) error {
	idx.mu.Lock()
	defer idx.mu.Unlock()

	var files []string

	// Use git ls-files if in a git repo
	if isGitRepo(root) {
		cmd := exec.Command("git", "ls-files")
		cmd.Dir = root
		output, err := cmd.Output()
		if err == nil {
			files = strings.Split(strings.TrimSpace(string(output)), "\n")
			// Filter out empty strings
			filtered := make([]string, 0, len(files))
			for _, f := range files {
				if f != "" {
					filtered = append(filtered, f)
				}
			}
			idx.files = filtered
			idx.lastScan = time.Now()
			return nil
		}
	}

	// Fallback to filesystem walk
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil // Skip errors
		}

		// Skip hidden directories
		if d.IsDir() && strings.HasPrefix(d.Name(), ".") {
			return filepath.SkipDir
		}

		if !d.IsDir() {
			relPath, _ := filepath.Rel(root, path)
			files = append(files, relPath)
		}

		return nil
	})

	idx.files = files
	idx.lastScan = time.Now()
	return err
}

// fuzzyScore calculates a fuzzy match score for query against target
// Returns -1 if no match, higher scores for better matches
func fuzzyScore(query, target string) int {
	query = strings.ToLower(query)
	target = strings.ToLower(target)

	queryIdx := 0
	score := 0
	lastMatchIdx := -1

	for i := 0; i < len(target) && queryIdx < len(query); i++ {
		if target[i] == query[queryIdx] {
			// Bonus for consecutive matches
			if lastMatchIdx == i-1 {
				score += 3
			} else {
				score += 1
			}
			// Bonus for matching at word boundary
			if i == 0 || target[i-1] == '/' || target[i-1] == '_' || target[i-1] == '.' {
				score += 2
			}
			lastMatchIdx = i
			queryIdx++
		}
	}

	// All query chars must match
	if queryIdx < len(query) {
		return -1
	}

	// Bonus for shorter targets (more precise match)
	score += 10 - minInt(10, len(target)/10)

	return score
}

// minInt returns the minimum of two ints
func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Search performs fuzzy search on the indexed files
func (idx *FileIndex) Search(query string, limit int) []FileMatch {
	idx.mu.RLock()
	defer idx.mu.RUnlock()

	var matches []FileMatch

	for _, file := range idx.files {
		// Score against the base filename for better relevance
		score := fuzzyScore(query, filepath.Base(file))
		if score > 0 {
			matches = append(matches, FileMatch{
				Path:  file,
				Score: score,
			})
		}
	}

	// Sort by score descending
	sort.Slice(matches, func(i, j int) bool {
		return matches[i].Score > matches[j].Score
	})

	if len(matches) > limit {
		matches = matches[:limit]
	}

	return matches
}

// detectFileSearch checks if @ is being typed and extracts the search query
// Returns true if file search should be active
func (m *model) detectFileSearch() {
	// Find last @ in input
	lastAt := strings.LastIndex(m.input, "@")

	if lastAt == -1 {
		m.showFileSearch = false
		return
	}

	// Check if @ is at the start or preceded by whitespace
	if lastAt > 0 {
		prevChar := m.input[lastAt-1]
		if prevChar != ' ' && prevChar != '\n' && prevChar != '\t' {
			m.showFileSearch = false
			return
		}
	}

	// Extract query after @
	query := m.input[lastAt+1:]

	// If query contains whitespace, file search is over
	if strings.ContainsAny(query, " \n\t") {
		m.showFileSearch = false
		return
	}

	// Update file search state
	m.showFileSearch = true
	m.fileSearchStartPos = lastAt
	m.fileSearchQuery = query

	// Perform search
	if query == "" {
		// Show all files when no query (up to limit)
		m.fileSearchResults = m.fileIndex.Search("", 20)
	} else {
		m.fileSearchResults = m.fileIndex.Search(query, 20)
	}

	// Reset selection if out of bounds
	if m.fileSearchSelection >= len(m.fileSearchResults) {
		m.fileSearchSelection = 0
	}
}

// insertSelectedFile replaces the @query with the selected file path
func (m *model) insertSelectedFile() {
	if !m.showFileSearch || len(m.fileSearchResults) == 0 {
		return
	}

	selected := m.fileSearchResults[m.fileSearchSelection]

	// Replace from @ to end of input with the selected file path
	m.input = m.input[:m.fileSearchStartPos] + "@" + selected.Path
	m.showFileSearch = false
	m.fileSearchQuery = ""
	m.fileSearchResults = []FileMatch{}
	m.fileSearchSelection = 0
}
