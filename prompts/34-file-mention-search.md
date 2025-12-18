# @ File Mention Search

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/</affects>
</metadata>

## Objective

Implement fuzzy file search triggered by `@` in the composer, allowing users to quickly mention and include files in their prompts.

<context>
Codex provides `@` file search in the composer for quickly finding and mentioning files. When the user types `@`, a search overlay appears with fuzzy-matched filenames. This enables:
- Quick file reference without typing full paths
- Fuzzy matching for partial names
- File content inclusion in context
- Navigation with keyboard

Similar to GitHub's file finder or VSCode's quick open (`Ctrl+P`).
</context>

## Requirements

<functional-requirements>
1. Trigger file search when user types `@` in composer
2. Show search overlay with fuzzy-matched files
3. Search behavior:
   - Search all files in working directory (respecting .gitignore)
   - Fuzzy matching (e.g., "mgo" matches "main.go")
   - Sort by relevance/recency
   - Limit results (e.g., top 20 matches)
4. Navigation:
   - Up/Down arrows to navigate results
   - Tab or Enter to select and insert
   - Esc to cancel search
   - Continue typing to refine search
5. Insert selected file as `@path/to/file`
6. Optional: Show file preview on selection
</functional-requirements>

<technical-requirements>
1. Create `FileSearchOverlay` component in TUI
2. Implement fuzzy matching algorithm (or use existing library)
3. Build file index at session start (with caching)
4. Handle large codebases efficiently (background indexing)
5. Respect .gitignore and hidden files
6. Track recently accessed files for better ranking
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/composer/composer.go` - Detect @ trigger
- `tui/internal/components/filesearch/filesearch.go` (CREATE) - Search overlay
- `tui/internal/app/update.go` - Handle file search events
- `tui/internal/services/fileindex.go` (CREATE) - File indexing service
</files-to-modify>

<file-search-ui>
```
┌─────────────────────────────────────────────────────┐
│ You: Can you help me fix the bug in @main          │
│                                    ▼                │
│ ┌──────────────────────────────────────────────────┐│
│ │ 🔍 main                                          ││
│ │ ────────────────────────────────────────────────│││
│ │ > main.go                          src/         ││
│ │   main_test.go                     src/         ││
│ │   main.py                          agent/       ││
│ │   mainwindow.go                    tui/         ││
│ │   maintenance.md                   docs/        ││
│ │                                                  ││
│ │ [↑↓: Navigate] [Tab/Enter: Select] [Esc: Cancel]││
│ └──────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```
</file-search-ui>

<fuzzy-matching>
```go
// Simple fuzzy match scoring
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
    score += 10 - min(10, len(target)/10)

    return score
}

// Search files with fuzzy matching
func searchFiles(query string, files []string, limit int) []FileMatch {
    var matches []FileMatch

    for _, file := range files {
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
```
</fuzzy-matching>

<file-indexing>
```go
type FileIndex struct {
    files    []string
    lastScan time.Time
    mu       sync.RWMutex
}

func (idx *FileIndex) Scan(root string) error {
    idx.mu.Lock()
    defer idx.mu.Unlock()

    var files []string

    // Use git ls-files if in a git repo
    if isGitRepo(root) {
        output, err := exec.Command("git", "ls-files").Output()
        if err == nil {
            files = strings.Split(strings.TrimSpace(string(output)), "\n")
            idx.files = files
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

func (idx *FileIndex) Search(query string) []FileMatch {
    idx.mu.RLock()
    defer idx.mu.RUnlock()

    return searchFiles(query, idx.files, 20)
}
```
</file-indexing>

## Acceptance Criteria

<criteria>
- [ ] Typing `@` in composer opens file search overlay
- [ ] Fuzzy matching finds files by partial name
- [ ] Results sorted by relevance score
- [ ] Up/Down arrows navigate results
- [ ] Tab or Enter inserts selected file path
- [ ] Esc closes search without insertion
- [ ] Typing continues to refine search
- [ ] Works with large codebases (1000+ files)
- [ ] Respects .gitignore when using git ls-files
- [ ] Shows file directory for disambiguation
- [ ] Search is case-insensitive
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test fuzzy matching with various patterns
3. Test performance with large directories
4. Run `zig build build-go` to ensure compilation succeeds
5. Rename this file from `34-file-mention-search.md` to `34-file-mention-search.complete.md`
</completion>
