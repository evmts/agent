"""Dangerous command detection."""


# Dangerous commands that should always be flagged
DANGEROUS_COMMANDS = [
    "rm -rf /",
    "rm -rf /*",
    "rm -rf ~",
    "rm -rf ~/*",
    "dd if=",
    "mkfs.",
    ":(){ :|:& };:",  # fork bomb
    "chmod -R 777 /",
    "chown -R",
    "> /dev/sda",
    "mv / ",
]

# Dangerous prefixes that indicate destructive operations
DANGEROUS_PREFIXES = [
    "rm -rf /",
    "dd if=/dev/zero of=/dev/",
    "mkfs.",
    "chmod -R 777 /",
]

# Additional patterns to watch for
DANGEROUS_PATTERNS = [
    "rm -rf",  # General rm -rf is risky
    "dd if=/dev/",
    "dd of=/dev/",
]


def is_dangerous_bash_command(command: str) -> tuple[bool, str]:
    """
    Check if a bash command is potentially dangerous.

    Args:
        command: The bash command to check

    Returns:
        Tuple of (is_dangerous, warning_message)
    """
    cmd = command.strip()

    # Check exact matches
    for dangerous in DANGEROUS_COMMANDS:
        if dangerous in cmd:
            return True, f"⚠️  WARNING: This command contains '{dangerous}' which is EXTREMELY DANGEROUS"

    # Check prefixes
    for prefix in DANGEROUS_PREFIXES:
        if cmd.startswith(prefix):
            return True, f"⚠️  WARNING: Commands starting with '{prefix}' can destroy your system"

    # Check for general risky patterns
    for pattern in DANGEROUS_PATTERNS:
        if pattern in cmd:
            return True, f"⚠️  WARNING: This command contains '{pattern}' which can be destructive"

    return False, ""
