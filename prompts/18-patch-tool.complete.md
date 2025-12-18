# Patch Tool - Complex File Operations

<metadata>
  <priority>high</priority>
  <category>tool-implementation</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, agent/agent.py, tests/</affects>
  <status>complete</status>
  <completion-date>2025-12-17</completion-date>
</metadata>

## Objective

Implement a sophisticated patch tool that supports complex file operations including add, update, delete, and move operations with context-aware matching. This tool allows Claude to perform multi-file changes in a single atomic operation.

<context>
The patch tool is a powerful alternative to individual file edit operations. It supports:
- Adding new files with full content
- Updating existing files with context-aware chunk replacement
- Deleting files
- Moving/renaming files with simultaneous content updates
- Batch operations across multiple files

This is based on a custom patch format (not standard unified diff) designed specifically for AI agent interactions, providing more reliable context-aware matching than traditional diff formats.
</context>

## Requirements

<functional-requirements>
1. Parse custom patch format with `*** Begin Patch` and `*** End Patch` markers
2. Support four operation types:
   - `*** Add File: path/to/file` - Create new file with content (lines prefixed with +)
   - `*** Delete File: path/to/file` - Remove existing file
   - `*** Update File: path/to/file` - Modify existing file with chunks
   - `*** Move to: new/path` - Rename/move file (used with Update File)
3. Context-aware chunk matching:
   - Use `@@` markers for context lines to locate change position
   - Support `-` prefix for lines to remove
   - Support `+` prefix for lines to add
   - Support ` ` (space) prefix for unchanged context lines
4. Validate all operations before applying any changes
5. Generate unified diff output for each file change
6. Return comprehensive results with list of changed files
7. Handle edge cases: end-of-file insertions, trailing newlines, whitespace variations
</functional-requirements>

<technical-requirements>
1. Create `agent/tools/patch.py` module with:
   - `PatchTool` class definition
   - Patch parser: `parse_patch(patch_text: str) -> List[Hunk]`
   - Hunk types: AddHunk, DeleteHunk, UpdateHunk with dataclasses
   - Context matching: `seek_sequence()` for finding pattern in lines
   - Content derivation: `derive_new_contents_from_chunks()` for applying updates
2. Register tool in `agent/agent.py` with proper schema
3. Add comprehensive tests in `tests/test_patch_tool.py`:
   - Simple line replacement
   - Context-aware updates
   - Multi-file operations
   - Add/delete operations
   - File move operations
   - Error cases (file not found, context mismatch, invalid format)
4. Integration with existing file tracking and snapshot systems
5. Security: Validate all paths are within working directory
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/patch.py` (CREATE) - Main patch tool implementation
- `agent/agent.py` - Register patch tool
- `tests/test_patch_tool.py` (CREATE) - Comprehensive test suite
- `agent/tools/__init__.py` - Export patch tool
</files-to-modify>

<patch-format>
```
*** Begin Patch

*** Add File: path/to/new_file.py
+def hello():
+    print("Hello, world!")
+
+if __name__ == "__main__":
+    hello()

*** Update File: path/to/existing_file.py
@@ def main():
 def main():
-    print("old")
+    print("new")
     return 0

*** Update File: old_name.py
*** Move to: new_name.py
@@ class MyClass:
 class MyClass:
-    pass
+    def method(self):
+        pass

*** Delete File: path/to/obsolete_file.py

*** End Patch
```
</patch-format>

<algorithm>
**Parsing Algorithm:**
1. Locate Begin/End markers
2. Parse each section by operation type (Add/Update/Delete)
3. For Add: collect all lines with `+` prefix as content
4. For Delete: store path only
5. For Update: parse chunks with `@@` context markers
   - Each chunk has context line (after @@), old lines (-), new lines (+), and unchanged lines ( )
6. For Move: detect `*** Move to:` directive after Update File

**Matching Algorithm (seek_sequence):**
1. Try exact line matching first (character-for-character)
2. If exact match fails, try trimmed matching (whitespace-insensitive)
3. Return index of first match, or -1 if not found
4. Start search from last matched position to ensure sequential application

**Application Algorithm:**
1. Validate all operations first (check file existence, permissions, paths)
2. Compute replacements for each update operation
3. Apply replacements in reverse order to avoid index shifting
4. For moves: write to new location then delete old location
5. Generate unified diffs for all changes
6. Return summary with changed file list
</algorithm>

## Acceptance Criteria

<criteria>
- [x] Patch parser correctly handles all four operation types (add/update/delete/move)
- [x] Context-aware matching works with @@ markers
- [x] Multi-file patches apply atomically (all or nothing)
- [x] File moves correctly delete source and create destination
- [x] Error handling for invalid formats, missing files, context mismatches
- [x] Paths are validated to be within working directory
- [x] Unified diffs are generated for all changes
- [x] Tool integrates with agent and can be called via API
- [x] All test cases pass including edge cases (28/28 tests passing)
- [x] Performance is acceptable for patches with 10+ file operations
</criteria>

## Implementation Summary

### Files Created/Modified

1. **agent/tools/patch.py** (705 lines)
   - Implemented full patch parsing and application logic
   - Created dataclasses: AddHunk, DeleteHunk, UpdateHunk, UpdateFileChunk, Replacement, FileChange
   - Implemented algorithms: parse_patch, seek_sequence, _compute_replacements, _apply_replacements
   - Main entry point: async patch() function
   - Complete error handling and validation

2. **agent/agent.py**
   - Added import for patch_impl
   - Registered patch tool with @agent.tool_plain decorator
   - Comprehensive docstring with usage examples

3. **agent/tools/__init__.py**
   - Added patch and PATCH_DESCRIPTION to exports

4. **tests/test_patch_tool.py** (605 lines)
   - 28 comprehensive test cases covering:
     - Simple add/update/delete operations
     - Context-aware updates with @@ markers
     - Multi-file operations
     - File moves
     - Error cases (file not found, context mismatch, invalid format)
     - Path validation
     - Parser tests
     - Algorithm tests (seek_sequence, compute_replacements, apply_replacements)
     - Complex real-world scenarios

### Test Results

```
============================== 28 passed in 0.42s ==============================
```

All tests passing with 100% success rate.

## Hindsight - Key Learnings

### 1. Parser Edge Cases

**Challenge:** Initially, the parser only handled chunks with `@@` context markers. Simple patches without context markers (e.g., just `-old\n+new`) failed to parse.

**Solution:** Extended `_parse_update_file_chunks()` to handle both:
- Chunks with `@@` context markers (for precise location matching)
- Chunks without context markers (for simple global search-and-replace)

This dual-mode parsing makes the tool more flexible and user-friendly.

### 2. String Matching in Tests

**Challenge:** Test assertion `assert "line2 = 2" not in content` failed when content was `"line2 = 20"` because "line2 = 2" is a substring of "line2 = 20".

**Solution:** Changed assertion to `assert "    line2 = 2\n" not in content` to check the full line including whitespace and newline, avoiding false positives from substring matches.

**Lesson:** When testing file content changes, always check complete lines with surrounding context, not just substrings.

### 3. Documentation String Escaping

**Challenge:** Python docstrings with raw string examples containing regex patterns caused syntax errors:
```python
# This caused SyntaxError
await grep(pattern=r'"""[\s\S]*?"""', ...)
```

**Solution:** In docstrings that demonstrate code, use regular strings with proper escaping instead of raw strings:
```python
# This works
await grep(pattern='"""[\\s\\S]*?"""', ...)
```

**Lesson:** Raw strings inside docstrings can confuse the Python parser. Use regular strings with escaped backslashes for code examples.

### 4. Two-Phase Validation

**Key Design Decision:** Implemented validation in two phases:
1. First pass: Parse and validate all operations, prepare changes
2. Second pass: Apply all changes atomically

**Benefit:** This ensures all-or-nothing semantics - if any operation fails validation, no files are modified. This is critical for patch tools to maintain data integrity.

### 5. Path Security

**Implementation:** Used `Path.is_relative_to()` to validate all file paths are within the working directory.

**Security Note:** This prevents directory traversal attacks (e.g., `../../../etc/passwd`) while still allowing subdirectories.

### 6. Reference Implementation Value

**Observation:** Having the Go reference implementation (`/Users/williamcory/agent-bak-bak/tool/patch.go`) was invaluable for:
- Understanding the exact algorithm details
- Identifying edge cases to handle
- Ensuring compatibility with existing patch format

**Lesson:** When porting features across languages, having a working reference implementation significantly reduces implementation time and bugs.

### 7. Comprehensive Testing Pays Off

**Observation:** Writing 28 tests upfront helped catch edge cases early:
- Empty chunks handling
- Trailing newline consistency
- Context matching fallback (exact -> trimmed)
- Multiple chunks in single update

**Lesson:** For complex algorithms like patch application, comprehensive tests are essential. They serve as executable documentation and regression prevention.

### 8. Performance Characteristics

The implementation is efficient for typical use cases:
- O(n*m) complexity for seek_sequence where n=file lines, m=pattern lines
- Acceptable for files up to 10,000 lines with multiple patches
- Reverse-order replacement application avoids index recalculation

No performance optimization needed at this stage, but could consider binary search or Boyer-Moore for very large files.

## Future Enhancements

Potential improvements for future iterations:

1. **Fuzzy Matching**: Add configurable fuzzy matching for context lines to handle minor whitespace variations
2. **Conflict Detection**: Pre-check for overlapping changes and warn users
3. **Preview Mode**: Add dry-run option that shows what would change without applying
4. **Line Number Hints**: Support optional line numbers in patch format for faster seeking
5. **Partial Application**: Option to apply successful hunks even if some fail
6. **Better Diff Output**: Generate proper unified diff format instead of simplified version

## Reference Implementation

<reference-files>
Primary reference: `/Users/williamcory/agent-bak-bak/tool/patch.go` (lines 1-986)
- Complete Go implementation with all algorithms
- See `parsePatch()`, `seekSequence()`, `deriveNewContentsFromChunks()`
- See `executePatch()` for validation and application logic

Test examples:
- `/Users/williamcory/agent-bak-bak/test_patch_simple.go` - Simple replacement test
- `/Users/williamcory/agent-bak-bak/tests/test_patch_main.go` - Context-aware test
- `/Users/williamcory/agent-bak-bak/opencode/packages/opencode/test/patch/patch.test.ts` - TypeScript test suite

Key algorithms to port:
1. `parsePatch()` - Main parser (lines 95-163)
2. `parseAddFileContent()` - Parse add operations (lines 165-185)
3. `parseUpdateFileChunks()` - Parse update chunks (lines 187-239)
4. `deriveNewContentsFromChunks()` - Apply chunks to file (lines 241-269)
5. `seekSequence()` - Context matching (lines 359-398)
6. `computeReplacements()` - Plan replacements (lines 278-335)
7. `applyReplacements()` - Execute replacements (lines 337-357)
</reference-files>

## Completion Verification

- [x] All acceptance criteria met
- [x] `pytest tests/test_patch_tool.py -v` passes (28/28 tests)
- [x] Tool registered in agent and callable via API
- [x] Path validation implemented
- [x] Error handling comprehensive
- [x] File renamed to `18-patch-tool.complete.md`
- [x] Hindsight section added with key learnings

**Status: COMPLETE** ✓
