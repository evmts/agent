# Patch Tool - Complex File Operations

<metadata>
  <priority>high</priority>
  <category>tool-implementation</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, agent/agent.py, tests/</affects>
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

<example-implementation>
```python
from dataclasses import dataclass
from typing import List, Optional, Tuple
import os

@dataclass
class AddHunk:
    type: str = "add"
    path: str = ""
    contents: str = ""

@dataclass
class DeleteHunk:
    type: str = "delete"
    path: str = ""

@dataclass
class UpdateFileChunk:
    old_lines: List[str]
    new_lines: List[str]
    change_context: str
    is_end_of_file: bool = False

@dataclass
class UpdateHunk:
    type: str = "update"
    path: str = ""
    move_path: Optional[str] = None
    chunks: List[UpdateFileChunk] = None

def parse_patch(patch_text: str) -> List:
    """Parse patch text into list of hunks."""
    lines = patch_text.split('\n')

    # Find Begin/End markers
    begin_idx = next((i for i, line in enumerate(lines)
                     if line.strip() == "*** Begin Patch"), -1)
    end_idx = next((i for i, line in enumerate(lines)
                   if line.strip() == "*** End Patch"), -1)

    if begin_idx == -1 or end_idx == -1:
        raise ValueError("Invalid patch format: missing markers")

    hunks = []
    i = begin_idx + 1

    while i < end_idx:
        line = lines[i]

        if line.startswith("*** Add File:"):
            path = line.split(":", 1)[1].strip()
            i += 1
            content, i = parse_add_content(lines, i, end_idx)
            hunks.append(AddHunk(path=path, contents=content))

        elif line.startswith("*** Delete File:"):
            path = line.split(":", 1)[1].strip()
            hunks.append(DeleteHunk(path=path))
            i += 1

        elif line.startswith("*** Update File:"):
            path = line.split(":", 1)[1].strip()
            i += 1

            # Check for move directive
            move_path = None
            if i < len(lines) and lines[i].startswith("*** Move to:"):
                move_path = lines[i].split(":", 1)[1].strip()
                i += 1

            chunks, i = parse_update_chunks(lines, i, end_idx)
            hunks.append(UpdateHunk(path=path, move_path=move_path,
                                   chunks=chunks))
        else:
            i += 1

    return hunks

def seek_sequence(lines: List[str], pattern: List[str],
                 start_index: int) -> int:
    """Find pattern in lines starting from start_index."""
    if not pattern:
        return -1

    # Try exact match
    for i in range(start_index, len(lines) - len(pattern) + 1):
        if all(lines[i+j] == pattern[j] for j in range(len(pattern))):
            return i

    # Try trimmed match
    for i in range(start_index, len(lines) - len(pattern) + 1):
        if all(lines[i+j].strip() == pattern[j].strip()
               for j in range(len(pattern))):
            return i

    return -1
```
</example-implementation>

<test-cases>
```python
def test_simple_replacement():
    """Test basic line replacement without context."""
    patch = """*** Begin Patch
*** Update File: test.txt
-old line
+new line
*** End Patch"""

    result = apply_patch(patch)
    assert result.success
    assert len(result.changed_files) == 1

def test_context_aware_update():
    """Test update with @@ context marker."""
    patch = """*** Begin Patch
*** Update File: test.py
@@ def main():
 def main():
-    print("old")
+    print("new")
     return 0
*** End Patch"""

    result = apply_patch(patch)
    assert result.success

def test_multi_file_operations():
    """Test adding, updating, and deleting in one patch."""
    patch = """*** Begin Patch
*** Add File: new.txt
+Hello World

*** Update File: existing.txt
-old
+new

*** Delete File: obsolete.txt
*** End Patch"""

    result = apply_patch(patch)
    assert len(result.changed_files) == 3

def test_file_move():
    """Test moving file with content update."""
    patch = """*** Begin Patch
*** Update File: old_name.py
*** Move to: new_name.py
@@ class MyClass:
 class MyClass:
-    pass
+    def method(self):
+        pass
*** End Patch"""

    result = apply_patch(patch)
    assert not os.path.exists("old_name.py")
    assert os.path.exists("new_name.py")

def test_error_context_not_found():
    """Test error when context line cannot be found."""
    patch = """*** Begin Patch
*** Update File: test.txt
@@ nonexistent context
-line
+replacement
*** End Patch"""

    with pytest.raises(ValueError, match="failed to find context"):
        apply_patch(patch)
```
</test-cases>

## Acceptance Criteria

<criteria>
- [ ] Patch parser correctly handles all four operation types (add/update/delete/move)
- [ ] Context-aware matching works with @@ markers
- [ ] Multi-file patches apply atomically (all or nothing)
- [ ] File moves correctly delete source and create destination
- [ ] Error handling for invalid formats, missing files, context mismatches
- [ ] Paths are validated to be within working directory
- [ ] Unified diffs are generated for all changes
- [ ] Tool integrates with agent and can be called via API
- [ ] All test cases pass including edge cases
- [ ] Performance is acceptable for patches with 10+ file operations
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

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_patch_tool.py -v` and ensure all tests pass
3. Test the tool manually via the API with complex multi-file patches
4. Verify integration with snapshot system and file tracking
5. Check performance with large patches (100+ line changes)
6. Rename this file from `18-patch-tool.md` to `18-patch-tool.complete.md`
</completion>
