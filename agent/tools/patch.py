"""
Patch tool for complex file operations.

Supports add, update, delete, and move operations with context-aware matching.
Based on custom patch format designed for AI agent interactions.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Tuple


@dataclass
class AddHunk:
    """Represents adding a new file."""
    type: str = "add"
    path: str = ""
    contents: str = ""


@dataclass
class DeleteHunk:
    """Represents deleting a file."""
    type: str = "delete"
    path: str = ""


@dataclass
class UpdateFileChunk:
    """Represents a single change within a file update."""
    old_lines: List[str] = field(default_factory=list)
    new_lines: List[str] = field(default_factory=list)
    change_context: str = ""
    is_end_of_file: bool = False


@dataclass
class UpdateHunk:
    """Represents updating an existing file."""
    type: str = "update"
    path: str = ""
    move_path: Optional[str] = None
    chunks: List[UpdateFileChunk] = field(default_factory=list)


@dataclass
class Replacement:
    """Represents a line replacement operation."""
    start_idx: int
    old_len: int
    new_segment: List[str]


@dataclass
class FileChange:
    """Represents a single file change for validation and diff generation."""
    file_path: str
    old_content: str
    new_content: str
    change_type: str  # "add", "update", "delete", "move"
    move_path: str = ""


def parse_patch(patch_text: str) -> List:
    """Parse patch text into list of hunks.

    Args:
        patch_text: The full patch text with Begin/End markers

    Returns:
        List of Hunk objects (AddHunk, DeleteHunk, or UpdateHunk)

    Raises:
        ValueError: If patch format is invalid
    """
    lines = patch_text.split('\n')

    # Find Begin/End markers
    begin_idx = -1
    end_idx = -1
    for i, line in enumerate(lines):
        if line.strip() == "*** Begin Patch":
            begin_idx = i
        if line.strip() == "*** End Patch":
            end_idx = i

    if begin_idx == -1 or end_idx == -1 or begin_idx >= end_idx:
        raise ValueError("Invalid patch format: missing Begin/End markers")

    hunks = []
    i = begin_idx + 1

    while i < end_idx:
        line = lines[i]

        if line.startswith("*** Add File:"):
            file_path = line.split(":", 1)[1].strip()
            i += 1
            content, i = _parse_add_file_content(lines, i, end_idx)
            hunks.append(AddHunk(path=file_path, contents=content))

        elif line.startswith("*** Delete File:"):
            file_path = line.split(":", 1)[1].strip()
            hunks.append(DeleteHunk(path=file_path))
            i += 1

        elif line.startswith("*** Update File:"):
            file_path = line.split(":", 1)[1].strip()
            i += 1

            # Check for move directive
            move_path = None
            if i < len(lines) and lines[i].startswith("*** Move to:"):
                move_path = lines[i].split(":", 1)[1].strip()
                i += 1

            chunks, i = _parse_update_file_chunks(lines, i, end_idx)
            hunks.append(UpdateHunk(path=file_path, move_path=move_path, chunks=chunks))
        else:
            i += 1

    if len(hunks) == 0:
        raise ValueError("No file changes found in patch")

    return hunks


def _parse_add_file_content(lines: List[str], start_idx: int, end_idx: int) -> Tuple[str, int]:
    """Parse the content for an Add File operation.

    Args:
        lines: All lines in the patch
        start_idx: Starting index for content
        end_idx: Index of End Patch marker

    Returns:
        Tuple of (content, next_index)
    """
    content_lines = []
    i = start_idx

    while i < end_idx and not lines[i].startswith("***"):
        if lines[i].startswith("+"):
            content_lines.append(lines[i][1:])
        i += 1

    # Join and handle trailing newline
    result = "\n".join(content_lines)
    return result, i


def _parse_update_file_chunks(lines: List[str], start_idx: int, end_idx: int) -> Tuple[List[UpdateFileChunk], int]:
    """Parse the chunks for an Update File operation.

    Args:
        lines: All lines in the patch
        start_idx: Starting index for chunks
        end_idx: Index of End Patch marker

    Returns:
        Tuple of (chunks, next_index)
    """
    chunks = []
    i = start_idx

    while i < end_idx and not lines[i].startswith("***"):
        if lines[i].startswith("@@"):
            # Parse context line
            context_line = lines[i][2:].strip()
            i += 1

            old_lines = []
            new_lines = []
            is_end_of_file = False

            # Parse change lines
            while i < end_idx and not lines[i].startswith("@@") and not lines[i].startswith("***"):
                change_line = lines[i]

                if change_line == "*** End of File":
                    is_end_of_file = True
                    i += 1
                    break

                if change_line.startswith(" "):
                    # Keep line - appears in both old and new
                    content = change_line[1:]
                    old_lines.append(content)
                    new_lines.append(content)
                elif change_line.startswith("-"):
                    # Remove line - only in old
                    old_lines.append(change_line[1:])
                elif change_line.startswith("+"):
                    # Add line - only in new
                    new_lines.append(change_line[1:])

                i += 1

            chunks.append(UpdateFileChunk(
                old_lines=old_lines,
                new_lines=new_lines,
                change_context=context_line,
                is_end_of_file=is_end_of_file
            ))
        elif lines[i].startswith("-") or lines[i].startswith("+") or lines[i].startswith(" "):
            # Handle changes without context marker
            old_lines = []
            new_lines = []
            is_end_of_file = False

            # Parse change lines
            while i < end_idx and not lines[i].startswith("@@") and not lines[i].startswith("***"):
                change_line = lines[i]

                if change_line == "*** End of File":
                    is_end_of_file = True
                    i += 1
                    break

                if change_line.startswith(" "):
                    # Keep line - appears in both old and new
                    content = change_line[1:]
                    old_lines.append(content)
                    new_lines.append(content)
                elif change_line.startswith("-"):
                    # Remove line - only in old
                    old_lines.append(change_line[1:])
                elif change_line.startswith("+"):
                    # Add line - only in new
                    new_lines.append(change_line[1:])
                else:
                    # End of chunk
                    break

                i += 1

            chunks.append(UpdateFileChunk(
                old_lines=old_lines,
                new_lines=new_lines,
                change_context="",  # No context marker
                is_end_of_file=is_end_of_file
            ))
        else:
            i += 1

    return chunks, i


def seek_sequence(lines: List[str], pattern: List[str], start_index: int) -> int:
    """Find the first occurrence of a pattern in lines starting from start_index.

    Tries exact match first, then trimmed match for flexibility.

    Args:
        lines: Lines to search in
        pattern: Pattern to find
        start_index: Index to start searching from

    Returns:
        Index of first match, or -1 if not found
    """
    if not pattern:
        return -1

    # Try exact match first
    for i in range(start_index, len(lines) - len(pattern) + 1):
        matches = True
        for j in range(len(pattern)):
            if lines[i + j] != pattern[j]:
                matches = False
                break
        if matches:
            return i

    # If exact match fails, try trimmed match (more flexible)
    for i in range(start_index, len(lines) - len(pattern) + 1):
        matches = True
        for j in range(len(pattern)):
            if lines[i + j].strip() != pattern[j].strip():
                matches = False
                break
        if matches:
            return i

    return -1


def _compute_replacements(original_lines: List[str], file_path: str, chunks: List[UpdateFileChunk]) -> List[Replacement]:
    """Determine what replacements to make for update chunks.

    Args:
        original_lines: Original file lines
        file_path: Path to file being updated
        chunks: Update chunks to apply

    Returns:
        List of Replacement objects

    Raises:
        ValueError: If context cannot be found or pattern doesn't match
    """
    replacements = []
    line_index = 0

    for chunk in chunks:
        # Handle context-based seeking
        if chunk.change_context:
            context_idx = seek_sequence(original_lines, [chunk.change_context], line_index)
            if context_idx == -1:
                raise ValueError(f"Failed to find context '{chunk.change_context}' in {file_path}")
            line_index = context_idx

        # Handle pure addition (no old lines)
        if not chunk.old_lines:
            insertion_idx = len(original_lines)
            if original_lines and original_lines[-1] == "":
                insertion_idx = len(original_lines) - 1
            replacements.append(Replacement(
                start_idx=insertion_idx,
                old_len=0,
                new_segment=chunk.new_lines
            ))
            continue

        # Try to match old lines in the file
        pattern = chunk.old_lines
        new_slice = chunk.new_lines
        found = seek_sequence(original_lines, pattern, line_index)

        # Retry without trailing empty line if not found
        if found == -1 and pattern and pattern[-1] == "":
            pattern = pattern[:-1]
            if new_slice and new_slice[-1] == "":
                new_slice = new_slice[:-1]
            found = seek_sequence(original_lines, pattern, line_index)

        if found != -1:
            replacements.append(Replacement(
                start_idx=found,
                old_len=len(pattern),
                new_segment=new_slice
            ))
            line_index = found + len(pattern)
        else:
            raise ValueError(f"Failed to find expected lines in {file_path}:\n{chr(10).join(chunk.old_lines)}")

    return replacements


def _apply_replacements(lines: List[str], replacements: List[Replacement]) -> List[str]:
    """Apply a set of replacements to lines.

    Applies in reverse order to avoid index shifting.

    Args:
        lines: Original lines
        replacements: Replacements to apply

    Returns:
        Lines with replacements applied
    """
    result = lines.copy()

    # Apply replacements in reverse order to avoid index shifting
    for replacement in reversed(replacements):
        # Build new slice: before + new segment + after
        before = result[:replacement.start_idx]
        after = result[replacement.start_idx + replacement.old_len:]

        result = before + replacement.new_segment + after

    return result


def _derive_new_contents_from_chunks(file_path: str, chunks: List[UpdateFileChunk]) -> str:
    """Apply update chunks to a file to derive new contents.

    Args:
        file_path: Path to file being updated
        chunks: Update chunks to apply

    Returns:
        New file contents

    Raises:
        ValueError: If file cannot be read or chunks cannot be applied
    """
    # Read original file
    try:
        with open(file_path, 'r') as f:
            content = f.read()
    except Exception as e:
        raise ValueError(f"Failed to read file {file_path}: {e}")

    original_lines = content.split('\n')

    # Drop trailing empty element for consistent line counting
    if original_lines and original_lines[-1] == "":
        original_lines = original_lines[:-1]

    replacements = _compute_replacements(original_lines, file_path, chunks)
    new_lines = _apply_replacements(original_lines, replacements)

    # Ensure trailing newline
    if not new_lines or new_lines[-1] != "":
        new_lines.append("")

    return '\n'.join(new_lines)


def _is_path_within_directory(file_path: str, directory: str) -> bool:
    """Check if a path is within a given directory.

    Args:
        file_path: Path to check
        directory: Directory to check against

    Returns:
        True if file_path is within directory
    """
    try:
        abs_file_path = Path(file_path).resolve()
        abs_dir = Path(directory).resolve()

        # Check if file path starts with directory
        return abs_file_path.is_relative_to(abs_dir)
    except (ValueError, RuntimeError):
        return False


def _generate_diff(file_path: str, old_content: str, new_content: str) -> str:
    """Create a simple unified diff between old and new content.

    Args:
        file_path: Path to file
        old_content: Original content
        new_content: New content

    Returns:
        Unified diff string
    """
    diff_lines = []
    diff_lines.append(f"--- {file_path}")
    diff_lines.append(f"+++ {file_path}")
    diff_lines.append("@@ -1 +1 @@")

    old_lines = old_content.split('\n')
    new_lines = new_content.split('\n')

    max_len = max(len(old_lines), len(new_lines))

    for i in range(max_len):
        old_line = old_lines[i] if i < len(old_lines) else ""
        new_line = new_lines[i] if i < len(new_lines) else ""

        if old_line != new_line:
            if old_line:
                diff_lines.append(f"-{old_line}")
            if new_line:
                diff_lines.append(f"+{new_line}")
        elif old_line:
            diff_lines.append(f" {old_line}")

    return '\n'.join(diff_lines)


async def patch(patch_text: str, working_dir: Optional[str] = None) -> str:
    """Apply a patch to modify multiple files.

    Supports adding, updating, deleting files with context-aware changes.

    Args:
        patch_text: The full patch text in custom format
        working_dir: Working directory for file operations (defaults to cwd)

    Returns:
        Summary of changes made

    Raises:
        ValueError: If patch is invalid or cannot be applied
    """
    # Parse the patch
    hunks = parse_patch(patch_text)

    # Get working directory
    if working_dir is None:
        working_dir = os.getcwd()

    # First pass: validate all operations and prepare file changes
    file_changes = []
    total_diff = []

    for hunk in hunks:
        if isinstance(hunk, AddHunk):
            file_path = os.path.join(working_dir, hunk.path)

            # Validate that path is within working directory
            if not _is_path_within_directory(file_path, working_dir):
                raise ValueError(f"File {hunk.path} is not in the current working directory")

            old_content = ""
            new_content = hunk.contents

            file_changes.append(FileChange(
                file_path=file_path,
                old_content=old_content,
                new_content=new_content,
                change_type="add"
            ))

            # Generate diff
            diff = _generate_diff(file_path, old_content, new_content)
            total_diff.append(diff)

        elif isinstance(hunk, DeleteHunk):
            file_path = os.path.join(working_dir, hunk.path)

            # Validate that path is within working directory
            if not _is_path_within_directory(file_path, working_dir):
                raise ValueError(f"File {hunk.path} is not in the current working directory")

            # Check if file exists
            if not os.path.isfile(file_path):
                raise ValueError(f"File not found or is directory: {file_path}")

            # Read content
            try:
                with open(file_path, 'r') as f:
                    old_content = f.read()
            except Exception as e:
                raise ValueError(f"Failed to read file for deletion {hunk.path}: {e}")

            file_changes.append(FileChange(
                file_path=file_path,
                old_content=old_content,
                new_content="",
                change_type="delete"
            ))

            # Generate diff
            diff = _generate_diff(file_path, old_content, "")
            total_diff.append(diff)

        elif isinstance(hunk, UpdateHunk):
            file_path = os.path.join(working_dir, hunk.path)

            # Validate that path is within working directory
            if not _is_path_within_directory(file_path, working_dir):
                raise ValueError(f"File {hunk.path} is not in the current working directory")

            # Check if file exists
            if not os.path.isfile(file_path):
                raise ValueError(f"File not found or is directory: {file_path}")

            # Read content
            try:
                with open(file_path, 'r') as f:
                    old_content = f.read()
            except Exception as e:
                raise ValueError(f"Failed to read file {hunk.path}: {e}")

            # Apply chunks to get new content
            new_content = _derive_new_contents_from_chunks(file_path, hunk.chunks)

            change_type = "update"
            move_path = ""
            if hunk.move_path:
                change_type = "move"
                move_path = os.path.join(working_dir, hunk.move_path)

                # Validate move destination is within working directory
                if not _is_path_within_directory(move_path, working_dir):
                    raise ValueError(f"Move destination {hunk.move_path} is not in the current working directory")

            file_changes.append(FileChange(
                file_path=file_path,
                old_content=old_content,
                new_content=new_content,
                change_type=change_type,
                move_path=move_path
            ))

            # Generate diff
            diff = _generate_diff(file_path, old_content, new_content)
            total_diff.append(diff)

    # Second pass: apply all changes
    changed_files = []

    for change in file_changes:
        if change.change_type == "add":
            # Create parent directories
            os.makedirs(os.path.dirname(change.file_path), exist_ok=True)

            # Write file
            with open(change.file_path, 'w') as f:
                f.write(change.new_content)

            changed_files.append(change.file_path)

        elif change.change_type == "update":
            # Write updated content
            with open(change.file_path, 'w') as f:
                f.write(change.new_content)

            changed_files.append(change.file_path)

        elif change.change_type == "move":
            # Create parent directories for destination
            os.makedirs(os.path.dirname(change.move_path), exist_ok=True)

            # Write to new location
            with open(change.move_path, 'w') as f:
                f.write(change.new_content)

            # Remove original
            os.remove(change.file_path)

            changed_files.append(change.move_path)

        elif change.change_type == "delete":
            # Delete file
            os.remove(change.file_path)

            changed_files.append(change.file_path)

    # Generate relative paths for output
    relative_paths = []
    for file_path in changed_files:
        try:
            rel_path = os.path.relpath(file_path, working_dir)
        except ValueError:
            rel_path = file_path
        relative_paths.append(rel_path)

    # Generate output
    summary = f"{len(file_changes)} files changed"
    output_lines = [f"Patch applied successfully. {summary}:"]
    for rel_path in relative_paths:
        output_lines.append(f"  {rel_path}")

    return '\n'.join(output_lines)


# Tool description for agent registration
PATCH_DESCRIPTION = """Apply a patch to modify multiple files. Supports adding, updating, and deleting files with context-aware changes.

Usage:
- The patchText parameter contains the full patch text in the custom format
- Patch format uses markers: *** Begin Patch, *** End Patch
- Supports operations: Add File, Delete File, Update File
- Update operations support context-aware chunk replacement
- File moves are supported with *** Move to: directive

Patch Format:
*** Begin Patch
*** Add File: path/to/new/file.py
+line 1 content
+line 2 content

*** Update File: path/to/existing/file.py
@@ context line for finding location
-old line to remove
+new line to add
 unchanged line

*** Delete File: path/to/old/file.py
*** End Patch"""
