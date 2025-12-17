"""
Edit tool for performing string replacements in files.

This is an internal implementation used by the MultiEdit tool.
It provides sophisticated fallback replacement strategies to handle
whitespace and indentation variations.

Based on the Go reference implementation from agent-bak-bak/tool/edit.go.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Callable

# Error messages (matching Go implementation)
ERROR_OLD_STRING_NOT_FOUND = "oldString not found in content"
ERROR_OLD_STRING_MULTIPLE = (
    "oldString found multiple times and requires more code context "
    "to uniquely identify the intended match"
)
ERROR_SAME_OLD_NEW = "oldString and newString must be different"
ERROR_FILE_OUTSIDE_CWD = "file {} is not in the current working directory"
ERROR_FILE_NOT_FOUND = "file not found: {}"
ERROR_PATH_IS_DIRECTORY = "path is a directory, not a file: {}"

# Similarity thresholds
BLOCK_ANCHOR_SIMILARITY_THRESHOLD = 0.3
CONTEXT_AWARE_SIMILARITY_THRESHOLD = 0.5

# Default file permissions for new files
DEFAULT_FILE_MODE = 0o644


@dataclass
class EditResult:
    """Result from an edit operation."""

    success: bool
    file_path: str
    diff: str = ""
    error: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)


def resolve_and_validate_path(
    file_path: str, working_dir: str | None = None
) -> tuple[str, str | None]:
    """
    Resolve file path to absolute and validate within working directory.

    Args:
        file_path: Path provided by user
        working_dir: Working directory (defaults to cwd)

    Returns:
        Tuple of (absolute_path, error_message or None)
    """
    cwd = working_dir or os.getcwd()

    # Convert to absolute
    if not os.path.isabs(file_path):
        file_path = os.path.join(cwd, file_path)

    # Resolve symlinks and normalize
    try:
        abs_file_path = os.path.realpath(file_path)
        abs_cwd = os.path.realpath(cwd)
    except OSError as e:
        return file_path, f"failed to resolve path: {e}"

    # Check containment
    try:
        rel_path = os.path.relpath(abs_file_path, abs_cwd)
        if rel_path.startswith(".."):
            return abs_file_path, ERROR_FILE_OUTSIDE_CWD.format(file_path)
    except ValueError:
        # Different drives on Windows
        return abs_file_path, ERROR_FILE_OUTSIDE_CWD.format(file_path)

    return abs_file_path, None


def levenshtein_similarity(a: str, b: str) -> float:
    """
    Calculate similarity ratio between two strings using SequenceMatcher.

    Returns a value between 0.0 (completely different) and 1.0 (identical).
    """
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


# --- Replacement Strategies ---


def simple_replacer(content: str, find: str) -> list[str]:
    """Try to find exact matches."""
    if find in content:
        return [find]
    return []


def line_trimmed_replacer(content: str, find: str) -> list[str]:
    """Match lines with trimmed whitespace."""
    original_lines = content.split("\n")
    search_lines = find.split("\n")

    # Remove trailing empty line if present
    if search_lines and search_lines[-1] == "":
        search_lines = search_lines[:-1]

    if not search_lines:
        return []

    matches = []

    for i in range(len(original_lines) - len(search_lines) + 1):
        all_match = True

        for j in range(len(search_lines)):
            original_trimmed = original_lines[i + j].strip()
            search_trimmed = search_lines[j].strip()

            if original_trimmed != search_trimmed:
                all_match = False
                break

        if all_match:
            # Calculate the actual matched text
            match_start_index = sum(
                len(original_lines[k]) + 1 for k in range(i)
            )
            match_end_index = match_start_index
            for k in range(len(search_lines)):
                match_end_index += len(original_lines[i + k])
                if k < len(search_lines) - 1:
                    match_end_index += 1  # newline

            matches.append(content[match_start_index:match_end_index])

    return matches


def block_anchor_replacer(content: str, find: str) -> list[str]:
    """Match blocks using first and last line anchors."""
    original_lines = content.split("\n")
    search_lines = find.split("\n")

    if len(search_lines) < 3:
        return []

    # Remove trailing empty line if present
    if search_lines and search_lines[-1] == "":
        search_lines = search_lines[:-1]

    if len(search_lines) < 3:
        return []

    first_line_search = search_lines[0].strip()
    last_line_search = search_lines[-1].strip()
    search_block_size = len(search_lines)

    # Collect all candidate positions
    candidates: list[tuple[int, int]] = []  # (start_line, end_line)

    for i in range(len(original_lines)):
        if original_lines[i].strip() != first_line_search:
            continue

        for j in range(i + 2, len(original_lines)):
            if original_lines[j].strip() == last_line_search:
                candidates.append((i, j))
                break

    if not candidates:
        return []

    # Single candidate with relaxed threshold
    if len(candidates) == 1:
        start_line, end_line = candidates[0]
        actual_block_size = end_line - start_line + 1

        similarity = 0.0
        lines_to_check = min(search_block_size - 2, actual_block_size - 2)

        if lines_to_check > 0:
            for j in range(1, min(search_block_size - 1, actual_block_size - 1)):
                original_line = original_lines[start_line + j].strip()
                search_line = search_lines[j].strip()
                similarity += levenshtein_similarity(original_line, search_line)
            similarity /= lines_to_check
        else:
            similarity = 1.0

        if similarity >= BLOCK_ANCHOR_SIMILARITY_THRESHOLD:
            match_start_index = sum(
                len(original_lines[k]) + 1 for k in range(start_line)
            )
            match_end_index = match_start_index
            for k in range(start_line, end_line + 1):
                match_end_index += len(original_lines[k])
                if k < end_line:
                    match_end_index += 1
            return [content[match_start_index:match_end_index]]
        return []

    # Multiple candidates - find best match
    best_match: tuple[int, int] | None = None
    max_similarity = -1.0

    for start_line, end_line in candidates:
        actual_block_size = end_line - start_line + 1
        similarity = 0.0
        lines_to_check = min(search_block_size - 2, actual_block_size - 2)

        if lines_to_check > 0:
            for j in range(1, min(search_block_size - 1, actual_block_size - 1)):
                original_line = original_lines[start_line + j].strip()
                search_line = search_lines[j].strip()
                similarity += levenshtein_similarity(original_line, search_line)
            similarity /= lines_to_check
        else:
            similarity = 1.0

        if similarity > max_similarity:
            max_similarity = similarity
            best_match = (start_line, end_line)

    if max_similarity >= BLOCK_ANCHOR_SIMILARITY_THRESHOLD and best_match:
        start_line, end_line = best_match
        match_start_index = sum(
            len(original_lines[k]) + 1 for k in range(start_line)
        )
        match_end_index = match_start_index
        for k in range(start_line, end_line + 1):
            match_end_index += len(original_lines[k])
            if k < end_line:
                match_end_index += 1
        return [content[match_start_index:match_end_index]]

    return []


def whitespace_normalized_replacer(content: str, find: str) -> list[str]:
    """Match with normalized whitespace."""

    def normalize_whitespace(text: str) -> str:
        return re.sub(r"\s+", " ", text).strip()

    normalized_find = normalize_whitespace(find)
    matches = []

    # Single line matches
    lines = content.split("\n")
    for line in lines:
        if normalize_whitespace(line) == normalized_find:
            matches.append(line)
        else:
            normalized_line = normalize_whitespace(line)
            if normalized_find in normalized_line:
                # Try to find the pattern with flexible whitespace
                words = find.split()
                if words:
                    pattern = r"\s+".join(re.escape(word) for word in words)
                    match = re.search(pattern, line)
                    if match:
                        matches.append(match.group())

    # Multi-line matches
    find_lines = find.split("\n")
    if len(find_lines) > 1:
        for i in range(len(lines) - len(find_lines) + 1):
            block = "\n".join(lines[i : i + len(find_lines)])
            if normalize_whitespace(block) == normalized_find:
                matches.append(block)

    return matches


def indentation_flexible_replacer(content: str, find: str) -> list[str]:
    """Match content ignoring indentation level."""

    def remove_indentation(text: str) -> str:
        lines = text.split("\n")
        non_empty_lines = [line for line in lines if line.strip()]

        if not non_empty_lines:
            return text

        # Find minimum indentation
        min_indent = float("inf")
        for line in non_empty_lines:
            match = re.match(r"^(\s*)", line)
            if match:
                indent_len = len(match.group(1))
                if indent_len < min_indent:
                    min_indent = indent_len

        if min_indent == float("inf"):
            min_indent = 0

        # Remove common indentation
        result_lines = []
        for line in lines:
            if line.strip() == "":
                result_lines.append(line)
            elif len(line) >= min_indent:
                result_lines.append(line[int(min_indent) :])
            else:
                result_lines.append(line)

        return "\n".join(result_lines)

    normalized_find = remove_indentation(find)
    content_lines = content.split("\n")
    find_lines = find.split("\n")

    matches = []
    for i in range(len(content_lines) - len(find_lines) + 1):
        block = "\n".join(content_lines[i : i + len(find_lines)])
        if remove_indentation(block) == normalized_find:
            matches.append(block)

    return matches


def escape_normalized_replacer(content: str, find: str) -> list[str]:
    """Handle escape sequences."""

    def unescape_string(s: str) -> str:
        replacements = {
            "\\n": "\n",
            "\\t": "\t",
            "\\r": "\r",
            "\\'": "'",
            '\\"': '"',
            "\\`": "`",
            "\\\\": "\\",
            "\\$": "$",
        }
        result = s
        for escaped, unescaped in replacements.items():
            result = result.replace(escaped, unescaped)
        return result

    unescaped_find = unescape_string(find)
    matches = []

    if unescaped_find in content:
        matches.append(unescaped_find)

    lines = content.split("\n")
    find_lines = unescaped_find.split("\n")

    for i in range(len(lines) - len(find_lines) + 1):
        block = "\n".join(lines[i : i + len(find_lines)])
        if unescape_string(block) == unescaped_find:
            matches.append(block)

    return matches


def trimmed_boundary_replacer(content: str, find: str) -> list[str]:
    """Try trimmed versions."""
    trimmed_find = find.strip()

    if trimmed_find == find:
        return []

    matches = []
    if trimmed_find in content:
        matches.append(trimmed_find)

    lines = content.split("\n")
    find_lines = find.split("\n")

    for i in range(len(lines) - len(find_lines) + 1):
        block = "\n".join(lines[i : i + len(find_lines)])
        if block.strip() == trimmed_find:
            matches.append(block)

    return matches


def context_aware_replacer(content: str, find: str) -> list[str]:
    """Use context anchors."""
    find_lines = find.split("\n")

    if len(find_lines) < 3:
        return []

    # Remove trailing empty line if present
    if find_lines and find_lines[-1] == "":
        find_lines = find_lines[:-1]

    if len(find_lines) < 3:
        return []

    content_lines = content.split("\n")
    first_line = find_lines[0].strip()
    last_line = find_lines[-1].strip()

    for i in range(len(content_lines)):
        if content_lines[i].strip() != first_line:
            continue

        for j in range(i + 2, len(content_lines)):
            if content_lines[j].strip() == last_line:
                block_lines = content_lines[i : j + 1]
                if len(block_lines) == len(find_lines):
                    matching_lines = 0
                    total_non_empty_lines = 0

                    for k in range(1, len(block_lines) - 1):
                        block_line = block_lines[k].strip()
                        find_line = find_lines[k].strip()

                        if block_line or find_line:
                            total_non_empty_lines += 1
                            if block_line == find_line:
                                matching_lines += 1

                    if (
                        total_non_empty_lines == 0
                        or matching_lines / total_non_empty_lines
                        >= CONTEXT_AWARE_SIMILARITY_THRESHOLD
                    ):
                        block = "\n".join(block_lines)
                        return [block]
                break

    return []


def multi_occurrence_replacer(content: str, find: str) -> list[str]:
    """Find all exact matches."""
    matches = []
    start_index = 0

    while True:
        index = content.find(find, start_index)
        if index == -1:
            break
        matches.append(find)
        start_index = index + len(find)

    return matches


# --- Main Replace Function ---


def replace(
    content: str, old_string: str, new_string: str, replace_all: bool
) -> tuple[str, str | None]:
    """
    Perform string replacement using multiple fallback strategies.

    Args:
        content: File content
        old_string: Text to find
        new_string: Text to replace with
        replace_all: Replace all occurrences

    Returns:
        Tuple of (new_content, error_message or None)
    """
    if old_string == new_string:
        return "", ERROR_SAME_OLD_NEW

    not_found = True

    # Try replacers in order
    replacers: list[Callable[[str, str], list[str]]] = [
        simple_replacer,
        line_trimmed_replacer,
        block_anchor_replacer,
        whitespace_normalized_replacer,
        indentation_flexible_replacer,
        escape_normalized_replacer,
        trimmed_boundary_replacer,
        context_aware_replacer,
        multi_occurrence_replacer,
    ]

    for replacer in replacers:
        matches = replacer(content, old_string)
        for search in matches:
            index = content.find(search)
            if index == -1:
                continue
            not_found = False

            if replace_all:
                return content.replace(search, new_string), None

            last_index = content.rfind(search)
            if index != last_index:
                continue  # Multiple occurrences, try next strategy

            # Single occurrence found
            return content[:index] + new_string + content[index + len(search) :], None

    if not_found:
        return "", ERROR_OLD_STRING_NOT_FOUND

    return "", ERROR_OLD_STRING_MULTIPLE


# --- Diff Generation ---


def create_diff(file_path: str, old_content: str, new_content: str) -> str:
    """
    Create a unified diff between old and new content.

    Args:
        file_path: Path to file (for header)
        old_content: Original content
        new_content: New content

    Returns:
        Unified diff string
    """
    if old_content == new_content:
        return ""

    old_lines = old_content.split("\n")
    new_lines = new_content.split("\n")

    # Simple unified diff header
    diff_lines = [f"--- {file_path}", f"+++ {file_path}"]

    # Generate context and changes
    changes: list[str] = []
    i = 0
    max_len = max(len(old_lines), len(new_lines))

    while i < max_len:
        # Find start of difference
        if i < len(old_lines) and i < len(new_lines) and old_lines[i] == new_lines[i]:
            i += 1
            continue

        # Found a difference
        context_start = max(0, i - 3)

        # Find end of difference
        j = i
        while j < len(old_lines) or j < len(new_lines):
            if j >= len(old_lines) or j >= len(new_lines):
                j += 1
                continue
            if old_lines[j] != new_lines[j]:
                j += 1
                continue
            break

        context_end = j + 3
        if context_end > max(len(old_lines), len(new_lines)):
            context_end = max(len(old_lines), len(new_lines))

        # Build hunk
        old_start = context_start + 1
        old_count = min(context_end, len(old_lines)) - context_start
        new_start = context_start + 1
        new_count = min(context_end, len(new_lines)) - context_start

        changes.append(f"@@ -{old_start},{old_count} +{new_start},{new_count} @@")

        # Add context and changes
        for k in range(context_start, context_end):
            if k < i or (
                k < len(old_lines) and k < len(new_lines) and old_lines[k] == new_lines[k]
            ):
                # Context line
                if k < len(old_lines):
                    changes.append(" " + old_lines[k])
                elif k < len(new_lines):
                    changes.append(" " + new_lines[k])
            else:
                # Changed lines
                if k < len(old_lines) and (
                    k >= len(new_lines) or old_lines[k] != new_lines[k]
                ):
                    changes.append("-" + old_lines[k])
                if k < len(new_lines) and (
                    k >= len(old_lines) or old_lines[k] != new_lines[k]
                ):
                    changes.append("+" + new_lines[k])

        i = context_end

    if changes:
        diff_lines.extend(changes)

    return "\n".join(diff_lines)


# --- Main Edit Function ---


async def edit(
    file_path: str,
    old_string: str,
    new_string: str,
    replace_all: bool = False,
    working_dir: str | None = None,
) -> dict[str, Any]:
    """
    Perform string replacement in a file.

    Args:
        file_path: Path to file to modify
        old_string: Text to replace (empty creates new file)
        new_string: Replacement text
        replace_all: Replace all occurrences
        working_dir: Working directory for path validation

    Returns:
        dict with success, file_path, diff, error, metadata
    """
    # Validate old_string != new_string
    if old_string == new_string:
        return {
            "success": False,
            "file_path": file_path,
            "error": ERROR_SAME_OLD_NEW,
        }

    # Resolve and validate path
    abs_file_path, path_error = resolve_and_validate_path(file_path, working_dir)
    if path_error:
        return {
            "success": False,
            "file_path": file_path,
            "error": path_error,
        }

    # Get relative path for output
    cwd = working_dir or os.getcwd()
    try:
        rel_path = os.path.relpath(abs_file_path, cwd)
    except ValueError:
        rel_path = abs_file_path

    # Handle empty old_string case (create new file)
    if old_string == "":
        content_new = new_string
        diff = create_diff(rel_path, "", content_new)

        # Create parent directories if needed
        parent_dir = os.path.dirname(abs_file_path)
        if parent_dir and not os.path.exists(parent_dir):
            try:
                os.makedirs(parent_dir, exist_ok=True)
            except OSError as e:
                return {
                    "success": False,
                    "file_path": file_path,
                    "error": f"failed to create directory: {e}",
                }

        # Write new file
        try:
            with open(abs_file_path, "w", encoding="utf-8") as f:
                f.write(content_new)
        except OSError as e:
            return {
                "success": False,
                "file_path": file_path,
                "error": f"failed to write file: {e}",
            }

        return {
            "success": True,
            "file_path": rel_path,
            "diff": diff,
            "metadata": {
                "filePath": abs_file_path,
                "created": True,
            },
        }

    # Check if file exists
    if not os.path.exists(abs_file_path):
        return {
            "success": False,
            "file_path": file_path,
            "error": ERROR_FILE_NOT_FOUND.format(abs_file_path),
        }

    if os.path.isdir(abs_file_path):
        return {
            "success": False,
            "file_path": file_path,
            "error": ERROR_PATH_IS_DIRECTORY.format(abs_file_path),
        }

    # Read the file content
    try:
        with open(abs_file_path, "r", encoding="utf-8") as f:
            content_old = f.read()
    except OSError as e:
        return {
            "success": False,
            "file_path": file_path,
            "error": f"failed to read file: {e}",
        }

    # Get file mode for preservation
    try:
        file_stat = os.stat(abs_file_path)
        file_mode = file_stat.st_mode
    except OSError:
        file_mode = DEFAULT_FILE_MODE

    # Perform the replacement
    content_new, replace_error = replace(content_old, old_string, new_string, replace_all)
    if replace_error:
        return {
            "success": False,
            "file_path": file_path,
            "error": replace_error,
        }

    # Generate diff before writing
    diff = create_diff(rel_path, content_old, content_new)

    # Write the new content back to the file
    try:
        with open(abs_file_path, "w", encoding="utf-8") as f:
            f.write(content_new)
        # Preserve file mode
        os.chmod(abs_file_path, file_mode)
    except OSError as e:
        return {
            "success": False,
            "file_path": file_path,
            "error": f"failed to write file: {e}",
        }

    return {
        "success": True,
        "file_path": rel_path,
        "diff": diff,
        "metadata": {
            "filePath": abs_file_path,
        },
    }
