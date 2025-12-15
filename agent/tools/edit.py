"""
File editing tools for partial file modifications.
Implements multiple fuzzy matching strategies inspired by OpenCode.
"""
import re
from pathlib import Path
from difflib import SequenceMatcher
from typing import Callable

from .file_operations import _validate_path


def _levenshtein_ratio(s1: str, s2: str) -> float:
    """Calculate Levenshtein similarity ratio between two strings."""
    return SequenceMatcher(None, s1, s2).ratio()


def _normalize_line_endings(text: str) -> str:
    """Normalize line endings to Unix format."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _normalize_whitespace(text: str) -> str:
    """Collapse multiple whitespace characters into single spaces."""
    return re.sub(r'[ \t]+', ' ', text)


def _normalize_indentation(text: str) -> str:
    """Remove common leading indentation from all lines."""
    lines = text.split('\n')
    if not lines:
        return text

    # Find minimum indentation (excluding empty lines)
    min_indent = float('inf')
    for line in lines:
        if line.strip():
            indent = len(line) - len(line.lstrip())
            min_indent = min(min_indent, indent)

    if min_indent == float('inf') or min_indent == 0:
        return text

    # Remove common indentation
    return '\n'.join(
        line[min_indent:] if line.strip() else line
        for line in lines
    )


def _unescape_string(text: str) -> str:
    """Unescape common escape sequences."""
    return (text
            .replace('\\n', '\n')
            .replace('\\t', '\t')
            .replace('\\r', '\r')
            .replace('\\"', '"')
            .replace("\\'", "'")
            .replace('\\\\', '\\'))


class Replacer:
    """Base class for replacement strategies."""

    name: str = "base"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        """
        Find a match in content for old_string.
        Returns (start, end) indices or None if not found.
        """
        raise NotImplementedError

    def find_all_matches(self, content: str, old_string: str) -> list[tuple[int, int]]:
        """Find all matches. Default implementation finds one match."""
        match = self.find_match(content, old_string)
        return [match] if match else []


class SimpleReplacer(Replacer):
    """Direct exact string matching."""

    name = "exact"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        idx = content.find(old_string)
        if idx >= 0:
            return (idx, idx + len(old_string))
        return None

    def find_all_matches(self, content: str, old_string: str) -> list[tuple[int, int]]:
        matches = []
        start = 0
        while True:
            idx = content.find(old_string, start)
            if idx < 0:
                break
            matches.append((idx, idx + len(old_string)))
            start = idx + 1
        return matches


class LineTrimmedReplacer(Replacer):
    """Match with line-by-line whitespace trimming."""

    name = "line_trimmed"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        content_lines = content.split('\n')
        old_lines = old_string.split('\n')

        # Trim each line
        old_trimmed = [line.strip() for line in old_lines]

        # Search for matching sequence
        for i in range(len(content_lines) - len(old_lines) + 1):
            content_trimmed = [content_lines[i + j].strip() for j in range(len(old_lines))]
            if content_trimmed == old_trimmed:
                # Calculate exact positions
                start_idx = sum(len(content_lines[k]) + 1 for k in range(i))
                end_idx = sum(len(content_lines[k]) + 1 for k in range(i + len(old_lines)))
                if end_idx > 0:
                    end_idx -= 1  # Remove trailing newline
                return (start_idx, end_idx)

        return None


class WhitespaceNormalizedReplacer(Replacer):
    """Match with whitespace normalization."""

    name = "whitespace_normalized"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        norm_content = _normalize_whitespace(content)
        norm_old = _normalize_whitespace(old_string)

        idx = norm_content.find(norm_old)
        if idx >= 0:
            # Map back to original positions
            orig_start = self._map_position(content, norm_content, idx)
            orig_end = self._map_position(content, norm_content, idx + len(norm_old))
            return (orig_start, orig_end)
        return None

    def _map_position(self, original: str, normalized: str, norm_pos: int) -> int:
        """Map position from normalized string back to original."""
        orig_pos = 0
        norm_idx = 0

        while norm_idx < norm_pos and orig_pos < len(original):
            if original[orig_pos] in ' \t':
                # Skip extra whitespace in original
                while orig_pos + 1 < len(original) and original[orig_pos + 1] in ' \t':
                    orig_pos += 1
            orig_pos += 1
            norm_idx += 1

        return orig_pos


class IndentationFlexibleReplacer(Replacer):
    """Match with flexible indentation."""

    name = "indentation_flexible"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        content_lines = content.split('\n')
        old_normalized = _normalize_indentation(old_string)
        old_lines = old_normalized.split('\n')

        for i in range(len(content_lines) - len(old_lines) + 1):
            # Get block and normalize its indentation
            block = '\n'.join(content_lines[i:i + len(old_lines)])
            block_normalized = _normalize_indentation(block)

            if block_normalized == old_normalized:
                start_idx = sum(len(content_lines[k]) + 1 for k in range(i))
                end_idx = start_idx + len(block)
                return (start_idx, end_idx)

        return None


class EscapeNormalizedReplacer(Replacer):
    """Match with escape sequence normalization."""

    name = "escape_normalized"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        unescaped_old = _unescape_string(old_string)
        idx = content.find(unescaped_old)
        if idx >= 0:
            return (idx, idx + len(unescaped_old))
        return None


class TrimmedBoundaryReplacer(Replacer):
    """Match with trimmed leading/trailing whitespace."""

    name = "trimmed_boundary"

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        trimmed_old = old_string.strip()
        idx = content.find(trimmed_old)
        if idx >= 0:
            return (idx, idx + len(trimmed_old))
        return None


class BlockAnchorReplacer(Replacer):
    """
    Use first and last lines as anchors with similarity scoring.
    Matches blocks where first/last lines are similar enough.
    """

    name = "block_anchor"
    SIMILARITY_THRESHOLD = 0.7

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        content_lines = content.split('\n')
        old_lines = old_string.strip().split('\n')

        if len(old_lines) < 2:
            return None

        first_anchor = old_lines[0].strip()
        last_anchor = old_lines[-1].strip()

        # Find potential start positions
        candidates = []
        for i, line in enumerate(content_lines):
            if _levenshtein_ratio(line.strip(), first_anchor) >= self.SIMILARITY_THRESHOLD:
                # Check if end anchor exists within reasonable range
                for j in range(i + len(old_lines) - 1, min(i + len(old_lines) * 2, len(content_lines))):
                    if _levenshtein_ratio(content_lines[j].strip(), last_anchor) >= self.SIMILARITY_THRESHOLD:
                        # Calculate similarity of the whole block
                        block = '\n'.join(content_lines[i:j + 1])
                        similarity = _levenshtein_ratio(
                            _normalize_whitespace(block),
                            _normalize_whitespace(old_string)
                        )
                        candidates.append((i, j + 1, similarity))

        if not candidates:
            return None

        # Return best match
        best = max(candidates, key=lambda x: x[2])
        if best[2] < self.SIMILARITY_THRESHOLD:
            return None

        start_idx = sum(len(content_lines[k]) + 1 for k in range(best[0]))
        end_idx = sum(len(content_lines[k]) + 1 for k in range(best[1]))
        if end_idx > 0:
            end_idx -= 1

        return (start_idx, end_idx)


class ContextAwareReplacer(Replacer):
    """
    Match blocks using context from surrounding lines.
    Uses 50% similarity threshold.
    """

    name = "context_aware"
    SIMILARITY_THRESHOLD = 0.5

    def find_match(self, content: str, old_string: str) -> tuple[int, int] | None:
        content_lines = content.split('\n')
        old_lines = old_string.split('\n')
        num_old_lines = len(old_lines)

        best_match = None
        best_similarity = self.SIMILARITY_THRESHOLD

        for i in range(len(content_lines) - num_old_lines + 1):
            block = '\n'.join(content_lines[i:i + num_old_lines])
            similarity = _levenshtein_ratio(block, old_string)

            if similarity > best_similarity:
                best_similarity = similarity
                start_idx = sum(len(content_lines[k]) + 1 for k in range(i))
                end_idx = start_idx + len(block)
                best_match = (start_idx, end_idx)

        return best_match


# List of replacers in order of preference (most precise first)
REPLACERS: list[Replacer] = [
    SimpleReplacer(),
    LineTrimmedReplacer(),
    WhitespaceNormalizedReplacer(),
    IndentationFlexibleReplacer(),
    EscapeNormalizedReplacer(),
    TrimmedBoundaryReplacer(),
    BlockAnchorReplacer(),
    ContextAwareReplacer(),
]


async def edit_file(
    path: str,
    old_string: str,
    new_string: str,
    replace_all: bool = False,
) -> str:
    """
    Edit a file by replacing old_string with new_string.

    Uses multiple matching strategies in order:
    1. Exact match
    2. Line-trimmed match (whitespace at line ends)
    3. Whitespace normalized match
    4. Indentation flexible match
    5. Escape normalized match
    6. Trimmed boundary match
    7. Block anchor match (first/last line similarity)
    8. Context aware match (50% similarity threshold)

    Args:
        path: Absolute or relative path to file
        old_string: The string to replace (can be exact or fuzzy)
        new_string: The replacement string
        replace_all: If True, replace all occurrences; if False, error on multiple matches

    Returns:
        Success message with details or error message
    """
    try:
        # Validate path
        file_path = _validate_path(path)
        if file_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

        if not file_path.exists():
            return f"Error: File not found: {path}"
        if not file_path.is_file():
            return f"Error: Not a file: {path}"

        # Validate that old_string and new_string are different
        if old_string == new_string:
            return "Error: old_string and new_string must be different"

        # Read file content and normalize line endings
        content = file_path.read_text()
        content = _normalize_line_endings(content)
        old_string = _normalize_line_endings(old_string)
        new_string = _normalize_line_endings(new_string)

        # Try each replacer in order
        successful_replacer = None
        matches: list[tuple[int, int]] = []

        for replacer in REPLACERS:
            if replace_all:
                matches = replacer.find_all_matches(content, old_string)
            else:
                match = replacer.find_match(content, old_string)
                matches = [match] if match else []

            if matches:
                successful_replacer = replacer
                break

        if not matches:
            # Provide helpful error message
            return (
                f"Error: Could not find a match for old_string in file: {path}\n"
                f"Tried {len(REPLACERS)} matching strategies (exact, line-trimmed, "
                f"whitespace-normalized, indentation-flexible, escape-normalized, "
                f"trimmed-boundary, block-anchor, context-aware).\n"
                f"Please ensure old_string matches the file content."
            )

        # Check for ambiguous matches
        if len(matches) > 1 and not replace_all:
            return (
                f"Error: Found {len(matches)} matches for old_string using "
                f"'{successful_replacer.name}' strategy.\n"
                f"Use replace_all=True to replace all occurrences, "
                f"or provide a more unique string with surrounding context."
            )

        # Perform replacement (replace from end to start to preserve indices)
        new_content = content
        for start, end in sorted(matches, reverse=True):
            new_content = new_content[:start] + new_string + new_content[end:]

        # Write back to file
        file_path.write_text(new_content)

        count = len(matches)
        occurrence_text = "occurrence" if count == 1 else "occurrences"
        strategy_info = f" (matched via '{successful_replacer.name}' strategy)"

        return f"Successfully replaced {count} {occurrence_text} in {path}{strategy_info}"

    except Exception as e:
        return f"Error editing file: {str(e)}"


async def multiedit(edits: list[dict]) -> str:
    """
    Apply multiple file edits atomically.

    All edits are validated before any are applied. If any edit fails validation,
    no changes are made to any files.

    Args:
        edits: List of edit dictionaries, each containing:
            - path: File path
            - old_string: String to replace
            - new_string: Replacement string
            - replace_all: Optional, default False

    Returns:
        Summary of all edits applied or error message
    """
    if not edits:
        return "Error: No edits provided"

    # Phase 1: Validate all edits
    validated_edits = []
    errors = []

    for i, edit in enumerate(edits):
        # Validate required fields
        if "path" not in edit:
            errors.append(f"Edit {i + 1}: Missing 'path' field")
            continue
        if "old_string" not in edit:
            errors.append(f"Edit {i + 1}: Missing 'old_string' field")
            continue
        if "new_string" not in edit:
            errors.append(f"Edit {i + 1}: Missing 'new_string' field")
            continue

        path = edit["path"]
        old_string = edit["old_string"]
        new_string = edit["new_string"]
        replace_all = edit.get("replace_all", False)

        # Validate path
        file_path = _validate_path(path)
        if file_path is None:
            errors.append(f"Edit {i + 1} ({path}): Access denied - path traversal detected")
            continue

        if not file_path.exists():
            errors.append(f"Edit {i + 1} ({path}): File not found")
            continue
        if not file_path.is_file():
            errors.append(f"Edit {i + 1} ({path}): Not a file")
            continue

        if old_string == new_string:
            errors.append(f"Edit {i + 1} ({path}): old_string and new_string must be different")
            continue

        # Read file content and normalize
        try:
            content = file_path.read_text()
            content = _normalize_line_endings(content)
            normalized_old = _normalize_line_endings(old_string)
            normalized_new = _normalize_line_endings(new_string)
        except Exception as e:
            errors.append(f"Edit {i + 1} ({path}): Error reading file: {e}")
            continue

        # Find matches using replacers
        successful_replacer = None
        matches: list[tuple[int, int]] = []

        for replacer in REPLACERS:
            if replace_all:
                matches = replacer.find_all_matches(content, normalized_old)
            else:
                match = replacer.find_match(content, normalized_old)
                matches = [match] if match else []

            if matches:
                successful_replacer = replacer
                break

        if not matches:
            errors.append(f"Edit {i + 1} ({path}): Could not find old_string in file")
            continue

        if len(matches) > 1 and not replace_all:
            errors.append(
                f"Edit {i + 1} ({path}): Found {len(matches)} matches. "
                f"Use replace_all=True or provide more context."
            )
            continue

        validated_edits.append({
            "file_path": file_path,
            "path": path,
            "content": content,
            "matches": matches,
            "new_string": normalized_new,
            "replacer": successful_replacer,
        })

    if errors:
        error_msg = "Validation failed. No changes were made.\n\n"
        error_msg += "Errors:\n" + "\n".join(f"  - {e}" for e in errors)
        return error_msg

    # Phase 2: Apply all edits
    results = []
    for edit_info in validated_edits:
        file_path = edit_info["file_path"]
        path = edit_info["path"]
        content = edit_info["content"]
        matches = edit_info["matches"]
        new_string = edit_info["new_string"]
        replacer = edit_info["replacer"]

        # Apply replacements (reverse order to preserve indices)
        new_content = content
        for start, end in sorted(matches, reverse=True):
            new_content = new_content[:start] + new_string + new_content[end:]

        # Write back
        try:
            file_path.write_text(new_content)
            count = len(matches)
            results.append(
                f"  - {path}: {count} replacement(s) via '{replacer.name}' strategy"
            )
        except Exception as e:
            results.append(f"  - {path}: ERROR writing file: {e}")

    return f"Successfully applied {len(validated_edits)} edit(s):\n" + "\n".join(results)


async def patch_file(path: str, unified_diff: str) -> str:
    """
    Apply a unified diff patch to a file.

    Args:
        path: Absolute or relative path to file
        unified_diff: Unified diff format patch

    Returns:
        Success or failure message
    """
    try:
        # Validate path
        file_path = _validate_path(path)
        if file_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

        if not file_path.exists():
            return f"Error: File not found: {path}"
        if not file_path.is_file():
            return f"Error: Not a file: {path}"

        # Read current file content
        content = file_path.read_text()
        lines = content.split("\n")

        # Parse unified diff
        diff_lines = unified_diff.strip().split("\n")

        # Skip header lines (---, +++, @@)
        patch_start = 0
        for i, line in enumerate(diff_lines):
            if line.startswith("@@"):
                patch_start = i + 1
                # Parse the hunk header to get line number
                # Format: @@ -start,count +start,count @@
                hunk_header = line.split("@@")[1].strip()
                parts = hunk_header.split()
                old_info = parts[0][1:]  # Remove leading '-'
                old_start = int(old_info.split(",")[0]) - 1  # 0-indexed
                break
        else:
            return "Error: Invalid unified diff format - no hunk header found"

        # Apply the patch
        result_lines = []
        original_index = 0
        patch_index = patch_start

        # Copy lines before the patch
        result_lines.extend(lines[:old_start])
        original_index = old_start

        # Process patch lines
        while patch_index < len(diff_lines):
            line = diff_lines[patch_index]

            if line.startswith(" "):
                # Context line - should match
                expected = line[1:]
                if original_index >= len(lines):
                    return f"Error: Patch does not match file content at line {original_index + 1}"
                if lines[original_index] != expected:
                    return f"Error: Patch does not match file content at line {original_index + 1}.\nExpected: {expected}\nGot: {lines[original_index]}"
                result_lines.append(lines[original_index])
                original_index += 1
            elif line.startswith("-"):
                # Line to remove
                expected = line[1:]
                if original_index >= len(lines):
                    return f"Error: Patch does not match file content at line {original_index + 1}"
                if lines[original_index] != expected:
                    return f"Error: Patch does not match file content at line {original_index + 1}.\nExpected to remove: {expected}\nGot: {lines[original_index]}"
                original_index += 1
                # Don't add to result (it's deleted)
            elif line.startswith("+"):
                # Line to add
                result_lines.append(line[1:])
                # Don't increment original_index (it's an addition)
            elif line.startswith("\\"):
                # "\ No newline at end of file" - ignore
                pass
            else:
                # Unknown line format
                return f"Error: Invalid diff line format: {line}"

            patch_index += 1

        # Copy remaining lines after the patch
        result_lines.extend(lines[original_index:])

        # Write the patched content
        new_content = "\n".join(result_lines)
        file_path.write_text(new_content)

        return f"Successfully applied patch to {path}"

    except Exception as e:
        return f"Error applying patch: {str(e)}"
