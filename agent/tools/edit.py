"""
File editing tools for partial file modifications.
"""
from pathlib import Path

from .file_operations import _validate_path


async def edit_file(
    path: str,
    old_string: str,
    new_string: str,
    replace_all: bool = False,
) -> str:
    """
    Edit a file by replacing old_string with new_string.

    Args:
        path: Absolute or relative path to file
        old_string: The exact string to replace
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

        # Read file content
        content = file_path.read_text()

        # Check if old_string exists
        if old_string not in content:
            return f"Error: old_string not found in file: {path}"

        # Count occurrences
        count = content.count(old_string)

        # If multiple occurrences and replace_all is False, error
        if count > 1 and not replace_all:
            return f"Error: Found {count} occurrences of old_string. Use replace_all=True to replace all occurrences, or provide a more unique string."

        # Perform replacement
        if replace_all:
            new_content = content.replace(old_string, new_string)
        else:
            # Replace only the first occurrence
            new_content = content.replace(old_string, new_string, 1)

        # Write back to file
        file_path.write_text(new_content)

        occurrence_text = "occurrence" if count == 1 else "occurrences"
        replaced_text = f"all {count}" if replace_all and count > 1 else "1"
        return f"Successfully replaced {replaced_text} {occurrence_text} in {path}"

    except Exception as e:
        return f"Error editing file: {str(e)}"


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
