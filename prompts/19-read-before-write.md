# Read-Before-Write Enforcement

<metadata>
  <priority>critical</priority>
  <category>safety-feature</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, core/state/, server/routes/</affects>
</metadata>

## Objective

Implement a safety mechanism that requires files to be read before they can be edited or written, preventing blind overwrites and ensuring agents have current file context.

<context>
In agent systems, allowing blind file writes without reading first can lead to data loss, race conditions, and conflicts. Claude Code and similar systems track when files are read and enforce that files must be read before modification. This prevents:
- Overwriting files without understanding their current contents
- Race conditions when files are modified externally
- Accidental data loss from stale state assumptions
- Merge conflicts from out-of-sync file states

The enforcement mechanism tracks file read timestamps and modification times, ensuring files haven't changed since they were last read.
</context>

## Requirements

<functional-requirements>
1. Track file read operations across the session lifecycle
2. Prevent Edit and Write tool operations on files that haven't been read
3. Detect when files have been modified externally since last read
4. Provide clear error messages explaining the read-before-write requirement
5. Support both per-session and global file tracking strategies
6. Handle symlinks and canonical paths correctly
7. Allow new file creation (no read required for non-existent files)
8. Clear tracking state when appropriate (session end, explicit reset)
</functional-requirements>

<technical-requirements>
1. Create `FileTimeTracker` class/struct to manage read timestamps
   - Track `lastRead` mapping: `filepath -> timestamp`
   - Method: `markRead(filepath)` - Record file read with current mtime
   - Method: `assertNotModified(filepath)` - Verify file hasn't changed
   - Handle path normalization (absolute paths, symlink resolution)

2. Integrate with Read tool
   - After successful read, call `MarkFileRead(filepath)`
   - Store file's modification time at read moment

3. Integrate with Write tool
   - Before writing, check if file exists
   - If exists, call `assertNotModified(filepath)`
   - Throw error if file not previously read
   - Throw error if file modified since last read
   - After successful write, update read timestamp

4. Integrate with Edit tool
   - Before editing, call `assertNotModified(filepath)`
   - Same error handling as Write tool

5. Error messages must be actionable:
   - "File {path} has not been read in this session. You MUST use the Read tool first before writing to existing files"
   - "File {path} has been modified since it was last read. Please use the Read tool again to get the latest contents"

6. Session-scoped tracking (Python implementation)
   - Track reads per session ID
   - Clear state when session ends

7. Global tracking (Go implementation)
   - Single global tracker instance
   - Shared across all agent operations
</technical-requirements>

## Implementation Guide

<files-to-modify>
**Python Backend:**
- `agent/tools/file_time.py` (new) - FileTimeTracker implementation
- `agent/tools/read.py` - Mark files as read after successful reads
- `agent/tools/write.py` - Enforce read-before-write on existing files
- `agent/tools/edit.py` - Enforce read-before-write
- `core/state.py` - Session-scoped tracking state
- `tests/test_agent/test_tools/test_file_safety.py` (new) - Test suite

**Go SDK/CLI (reference implementation):**
- `tool/write.go` - Contains reference implementation (lines 43-105)
- `tool/edit.go` - Contains enforcement logic (lines 134-150)
- `tool/read.go` - Should call MarkFileRead after successful reads
</files-to-modify>

<reference-implementation>
The Go implementation in `/Users/williamcory/agent-bak-bak/tool/write.go` provides a reference:

```go
type fileTimeTracker struct {
	lastRead map[string]time.Time
}

var globalFileTimeTracker = &fileTimeTracker{
	lastRead: make(map[string]time.Time),
}

func (ft *fileTimeTracker) markRead(filePath string) {
	// Normalize path and resolve symlinks
	absPath, err := filepath.Abs(filePath)
	if err == nil {
		filePath = absPath
	}
	realPath, err := filepath.EvalSymlinks(filePath)
	if err == nil {
		filePath = realPath
	}

	info, err := os.Stat(filePath)
	if err == nil {
		ft.lastRead[filePath] = info.ModTime()
	}
}

func (ft *fileTimeTracker) assertNotModified(filePath string) error {
	// Normalize path
	absPath, err := filepath.Abs(filePath)
	if err == nil {
		filePath = absPath
	}
	realPath, err := filepath.EvalSymlinks(filePath)
	if err == nil {
		filePath = realPath
	}

	lastRead, exists := ft.lastRead[filePath]
	if !exists {
		return fmt.Errorf("file %s has not been read in this session. You MUST use the Read tool first before writing to existing files", filePath)
	}

	info, err := os.Stat(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // File was deleted, that's okay
		}
		return fmt.Errorf("failed to stat file: %v", err)
	}

	if info.ModTime().After(lastRead) {
		return fmt.Errorf("file %s has been modified since it was last read. Please use the Read tool again to get the latest contents", filePath)
	}

	return nil
}
```

The TypeScript implementation in `/Users/williamcory/agent-bak-bak/opencode/packages/opencode/src/file/time.ts` shows session-scoped tracking:

```typescript
export namespace FileTime {
  export const state = Instance.state(() => {
    const read: {
      [sessionID: string]: {
        [path: string]: Date | undefined
      }
    } = {}
    return { read }
  })

  export function read(sessionID: string, file: string) {
    const { read } = state()
    read[sessionID] = read[sessionID] || {}
    read[sessionID][file] = new Date()
  }

  export async function assert(sessionID: string, filepath: string) {
    const time = get(sessionID, filepath)
    if (!time) throw new Error(`You must read the file ${filepath} before overwriting it. Use the Read tool first`)

    const stats = await Bun.file(filepath).stat()
    if (stats.mtime.getTime() > time.getTime()) {
      throw new Error(
        `File ${filepath} has been modified since it was last read.\nLast modification: ${stats.mtime.toISOString()}\nLast read: ${time.toISOString()}\n\nPlease read the file again before modifying it.`,
      )
    }
  }
}
```
</reference-implementation>

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

## Test Cases

<test-scenarios>
1. **Test: Prevent write without read**
   - Attempt to write existing file without reading first
   - Expected: Error "file has not been read in this session"

2. **Test: Allow write after read**
   - Read file, then write it
   - Expected: Write succeeds

3. **Test: Detect external modifications**
   - Read file, modify it externally, attempt to write
   - Expected: Error "file has been modified since it was last read"

4. **Test: Allow new file creation**
   - Write to non-existent file path
   - Expected: Write succeeds without requiring read

5. **Test: Path normalization**
   - Read file with relative path, write with absolute path
   - Expected: Tracker recognizes as same file

6. **Test: Symlink handling**
   - Read file via symlink, write via real path
   - Expected: Tracker recognizes as same file

7. **Test: Edit tool enforcement**
   - Attempt to edit file without reading first
   - Expected: Error "file has not been read in this session"

8. **Test: Session isolation (Python)**
   - Read file in session A, attempt write in session B
   - Expected: Error in session B (if session-scoped)

9. **Test: Timestamp updates after write**
   - Read, write, edit same file without re-reading
   - Expected: Edit succeeds (timestamp updated after write)
</test-scenarios>

## Acceptance Criteria

<criteria>
- [ ] FileTimeTracker implemented with markRead and assertNotModified methods
- [ ] Read tool marks files as read after successful operations
- [ ] Write tool enforces read-before-write for existing files
- [ ] Edit tool enforces read-before-write
- [ ] New file creation works without requiring read
- [ ] Symlinks and absolute/relative paths handled correctly
- [ ] Clear, actionable error messages when enforcement fails
- [ ] All test cases pass
- [ ] No performance degradation with file tracking
- [ ] Session state properly managed (creation/cleanup)
- [ ] External file modifications detected correctly
</criteria>

## Edge Cases to Handle

<edge-cases>
1. **File deleted after read**: Should allow write (creating new file)
2. **Very rapid read-modify-write cycles**: Timestamp precision handling
3. **Permission errors during stat**: Graceful error handling
4. **Large number of tracked files**: Memory management strategy
5. **Concurrent reads/writes**: Thread safety (if applicable)
6. **Case-sensitive vs case-insensitive filesystems**: Path comparison
7. **Network filesystems**: Clock skew between systems
8. **Soft links vs hard links**: Proper canonical path resolution
</edge-cases>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run the test suite: `pytest tests/test_agent/test_tools/test_file_safety.py`
3. Test manually with a Python session:
   ```python
   # Should fail
   agent.write_tool(filepath="existing.txt", content="new")

   # Should succeed
   agent.read_tool(filepath="existing.txt")
   agent.write_tool(filepath="existing.txt", content="new")
   ```
4. Run full integration tests: `pytest tests/`
5. Verify no regressions in existing functionality
6. Rename this file from `19-read-before-write.md` to `19-read-before-write.complete.md`
</completion>
