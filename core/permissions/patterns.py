"""Pattern matching logic for permissions."""

import fnmatch


def match_pattern(pattern: str, value: str) -> bool:
    """
    Check if a value matches a glob pattern.

    Supports:
    - Exact matches: "git status" matches "git status"
    - Wildcards: "git *" matches "git status", "git commit", etc.
    - Glob patterns: "*.py" matches "test.py", "main.py", etc.

    Args:
        pattern: The pattern to match against (supports * and ? wildcards)
        value: The value to check

    Returns:
        True if value matches pattern, False otherwise
    """
    # Handle wildcard-only pattern
    if pattern == "*":
        return True

    # Handle prefix wildcard: "git *"
    if pattern.endswith(" *"):
        prefix = pattern[:-2]  # Remove " *"
        return value.startswith(prefix)

    # Use fnmatch for complex globs
    return fnmatch.fnmatch(value, pattern)
