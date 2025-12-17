# File Modification Tracking

<metadata>
  <priority>high</priority>
  <category>reliability</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, server/routes/, core/</affects>
</metadata>

## Objective

Implement file modification time tracking to detect external changes and prevent concurrent edit conflicts, ensuring the agent doesn't overwrite files that have been modified since the last read.

<context>
From the OpenCode codebase analysis, there's existing file modification tracking in `/Users/williamcory/agent-bak-bak/tool/write.go`:

```go
// Store modification time after read
ft.lastRead[filePath] = info.ModTime()

// Check if file was modified externally
if info.ModTime().After(lastRead) {
    return fmt.Errorf("File %s has been modified since it was last read", filePath)
}
```

This pattern prevents the agent from overwriting files that have been changed by external tools (formatters, linters, IDEs, other processes) since the agent last read them. This is critical for preventing data loss and maintaining consistency in collaborative or automated workflows.
</context>

## Requirements

<functional-requirements>
1. Track file modification times (mtime) when files are read via Read tool
2. Before any write/edit operation, verify file hasn't been modified externally
3. Return clear error messages when external modifications are detected
4. Include timestamps in error messages for debugging (last read vs current mtime)
5. Provide option to force-write and override the safety check (with explicit user confirmation)
6. Clear tracking data when files are successfully written by the agent
7. Handle edge cases: file deletion, permission changes, symlinks
</functional-requirements>

<technical-requirements>
1. Add `FileTracker` class/struct to maintain `lastRead` map of filepath -> modification time
2. Integrate tracker into Read tool to capture mtimes
3. Add validation to Write and Edit tools before file operations
4. Use filesystem stat() calls to get current modification times
5. Store timestamps with nanosecond precision to detect rapid changes
6. Thread-safe/async-safe implementation for concurrent tool calls
7. Optional: Persist tracking data across server restarts (for long-running sessions)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/read.py` - Capture modification time when reading files
- `agent/tools/write.py` - Validate before writing
- `agent/tools/edit.py` - Validate before editing
- `core/file_tracker.py` (new) - Central file tracking service
- `core/state.py` - Integrate tracker into session state
- `server/routes/sessions.py` - Clear tracking on session reset
</files-to-modify>

<implementation-steps>
1. Create FileTracker service:
   ```python
   # core/file_tracker.py
   from pathlib import Path
   from datetime import datetime
   from typing import Dict, Optional

   class FileTracker:
       def __init__(self):
           self._last_read: Dict[str, float] = {}  # path -> mtime (seconds)

       def mark_read(self, file_path: str, mtime: float) -> None:
           """Store modification time after reading file"""
           self._last_read[str(Path(file_path).resolve())] = mtime

       def check_modified(self, file_path: str) -> tuple[bool, Optional[str]]:
           """Check if file was modified since last read.
           Returns (is_modified, error_message)"""
           path = str(Path(file_path).resolve())

           if path not in self._last_read:
               return False, None  # Never read before, safe to write

           try:
               current_mtime = Path(path).stat().st_mtime
               last_read = self._last_read[path]

               if current_mtime > last_read:
                   last_mod = datetime.fromtimestamp(current_mtime).isoformat()
                   last_read_time = datetime.fromtimestamp(last_read).isoformat()
                   msg = (f"File {file_path} has been modified since it was last read.\n"
                          f"Last modification: {last_mod}\n"
                          f"Last read: {last_read_time}\n\n"
                          f"Please read the file again before modifying it.")
                   return True, msg

               return False, None
           except FileNotFoundError:
               # File was deleted - clear tracking
               self.clear_file(path)
               return False, None

       def mark_written(self, file_path: str) -> None:
           """Update tracking after successful write"""
           path = str(Path(file_path).resolve())
           try:
               self._last_read[path] = Path(path).stat().st_mtime
           except FileNotFoundError:
               self.clear_file(path)

       def clear_file(self, file_path: str) -> None:
           """Remove tracking for a file"""
           path = str(Path(file_path).resolve())
           self._last_read.pop(path, None)

       def clear_all(self) -> None:
           """Clear all tracking data"""
           self._last_read.clear()
   ```

2. Integrate into Read tool:
   ```python
   # agent/tools/read.py
   async def read_file(file_path: str, tracker: FileTracker) -> str:
       path = Path(file_path)
       stat_info = path.stat()

       # Read file content...
       content = path.read_text()

       # Track modification time
       tracker.mark_read(str(path), stat_info.st_mtime)

       return content
   ```

3. Validate in Write tool:
   ```python
   # agent/tools/write.py
   async def write_file(file_path: str, content: str, tracker: FileTracker) -> str:
       # Check for external modifications
       is_modified, error_msg = tracker.check_modified(file_path)
       if is_modified:
           raise FileModifiedError(error_msg)

       # Perform write...
       Path(file_path).write_text(content)

       # Update tracking
       tracker.mark_written(file_path)

       return f"Successfully wrote to {file_path}"
   ```

4. Validate in Edit tool:
   ```python
   # agent/tools/edit.py
   async def edit_file(file_path: str, old_string: str, new_string: str, tracker: FileTracker) -> str:
       # Check for external modifications
       is_modified, error_msg = tracker.check_modified(file_path)
       if is_modified:
           raise FileModifiedError(error_msg)

       # Perform edit...
       content = Path(file_path).read_text()
       new_content = content.replace(old_string, new_string)
       Path(file_path).write_text(new_content)

       # Update tracking
       tracker.mark_written(file_path)

       return f"Successfully edited {file_path}"
   ```
</implementation-steps>

<edge-cases>
1. **Rapid successive writes**: Use nanosecond precision if available (st_mtime_ns)
2. **File deletion**: Clear tracking when file no longer exists
3. **Symlinks**: Always resolve to absolute path before tracking
4. **Permission changes**: Handle stat() failures gracefully
5. **Clock skew**: Consider filesystem timestamp precision limitations
6. **New files**: Don't block writes to files that haven't been read yet
7. **Force overwrite**: Optional parameter to bypass check (require explicit user intent)
</edge-cases>

## Example Scenarios

<scenario name="Normal workflow - safe">
1. Agent reads `src/app.py` (mtime: 2025-01-15 10:30:00)
2. Agent edits `src/app.py` at 10:31:00
3. File mtime still 10:30:00 → Safe to write ✓
4. After write, update tracking to new mtime
</scenario>

<scenario name="External modification - prevented">
1. Agent reads `config.json` (mtime: 10:00:00)
2. User manually edits `config.json` at 10:05:00 (formatter runs)
3. Agent tries to write to `config.json` at 10:06:00
4. Tracker detects mtime changed (10:05:00 > 10:00:00)
5. Error returned: "File modified since last read, please re-read" ✗
6. Agent must read file again before writing
</scenario>

<scenario name="File deletion">
1. Agent reads `temp.txt` (mtime: 09:00:00)
2. User deletes `temp.txt` at 09:30:00
3. Agent tries to write `temp.txt` at 09:45:00
4. Tracker allows write (file doesn't exist, can create new) ✓
5. Clear old tracking for deleted file
</scenario>

## Testing Strategy

<tests>
1. **Unit tests**:
   - FileTracker.mark_read() stores correct mtime
   - FileTracker.check_modified() detects changes
   - FileTracker.mark_written() updates tracking
   - Edge case: deleted files
   - Edge case: never-read files

2. **Integration tests**:
   - Read → Write sequence (should succeed)
   - Read → External modify → Write (should fail)
   - Read → External modify → Read → Write (should succeed)
   - Concurrent tool calls (thread safety)
   - Session reset clears tracking

3. **Manual test scenarios**:
   - Use agent to read a file
   - Manually edit file in external editor
   - Try to have agent modify the same file
   - Verify error message is clear and actionable
   - Re-read file and verify agent can now write
</tests>

## Acceptance Criteria

<criteria>
- [ ] FileTracker class created with mark_read, check_modified, mark_written methods
- [ ] Read tool captures and stores file modification times
- [ ] Write tool validates file hasn't been modified before writing
- [ ] Edit tool validates file hasn't been modified before editing
- [ ] Clear error messages include timestamps (last read vs current mtime)
- [ ] Tracking data cleared when files are successfully written
- [ ] Handles edge cases: deletion, permission changes, new files
- [ ] Thread-safe implementation for concurrent operations
- [ ] All unit tests pass
- [ ] Integration tests verify prevention of concurrent edits
- [ ] Manual testing confirms error messages are clear and helpful
</criteria>

## Execution Strategy

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

## Additional Considerations

<considerations>
1. **Performance**: Stat() calls add overhead - consider caching in memory
2. **Persistence**: For long-running servers, consider persisting tracker state to disk
3. **User experience**: Error messages should guide users to resolution (re-read file)
4. **Logging**: Log all modification conflicts for debugging and auditing
5. **Configuration**: Make tracking optional via environment variable (default: enabled)
6. **Future enhancement**: Automatic conflict resolution with 3-way merge
</considerations>

## Related Issues

<related>
- Issue #09: File Watcher - Could integrate with real-time file watching
- External tool integration: Formatters, linters trigger modifications
- Collaborative editing: Multiple agents/users editing same codebase
</related>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run test suite: `pytest tests/test_file_tracker.py`
3. Run integration tests: `pytest tests/test_tools/test_file_operations.py`
4. Manually test the scenarios described above
5. Verify no performance regression with large codebases
6. Rename this file from `24-file-modification-tracking.md` to `24-file-modification-tracking.complete.md`
7. Update documentation to describe the file tracking feature and error messages
</completion>
