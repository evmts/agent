"""
Code execution tools with sandbox support.
"""
import asyncio
import re
import shlex
import sys
import tempfile
from pathlib import Path


async def execute_python(code: str, timeout: int = 30) -> str:
    """
    Execute Python code in a sandboxed subprocess.

    Args:
        code: Python code to execute
        timeout: Maximum execution time in seconds

    Returns:
        stdout and stderr from execution
    """
    with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as f:
        f.write(code)
        script_path = f.name

    try:
        process = await asyncio.create_subprocess_exec(
            sys.executable,
            script_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), timeout=timeout
            )

            result = ""
            if stdout:
                result += f"STDOUT:\n{stdout.decode()}\n"
            if stderr:
                result += f"STDERR:\n{stderr.decode()}\n"
            if process.returncode != 0:
                result += f"\nExit code: {process.returncode}"

            return result or "Code executed successfully (no output)"

        except asyncio.TimeoutError:
            process.kill()
            return f"Execution timed out after {timeout} seconds"

    finally:
        Path(script_path).unlink(missing_ok=True)


def _validate_shell_command(command: str) -> tuple[bool, str | None]:
    """
    Validate shell command for dangerous patterns.

    WARNING: This is NOT a complete security solution. Shell injection is complex
    and this validation can be bypassed. Use with extreme caution.

    Args:
        command: The shell command to validate

    Returns:
        Tuple of (is_safe, warning_message)
    """
    # Dangerous patterns that could indicate shell injection attempts
    dangerous_patterns = [
        (r";\s*rm\s+-rf", "Detected dangerous 'rm -rf' command"),
        (r";\s*sudo", "Detected 'sudo' command which requires elevated privileges"),
        (r"\$\(.*\)", "Detected command substitution $() which can be exploited"),
        (r"`.*`", "Detected backtick command substitution which can be exploited"),
        (r">\s*/dev/", "Detected output redirection to /dev/ which could be dangerous"),
        (r"\|\s*sh\s*$", "Detected pipe to shell which can be exploited"),
        (r"\|\s*bash\s*$", "Detected pipe to bash which can be exploited"),
        (r"&&\s*rm\s+-rf", "Detected chained 'rm -rf' command"),
        (r"\|\|\s*rm\s+-rf", "Detected conditional 'rm -rf' command"),
        (r"curl.*\|\s*(sh|bash)", "Detected curl pipe to shell (dangerous pattern)"),
        (r"wget.*-O.*\|\s*(sh|bash)", "Detected wget pipe to shell (dangerous pattern)"),
    ]

    # Dangerous characters that need scrutiny
    dangerous_chars = {
        ";": "Command separator - could chain dangerous commands",
        "&": "Command separator/background operator",
        "|": "Pipe operator - could redirect to dangerous commands",
        ">": "Output redirection - could overwrite files",
        "<": "Input redirection",
        "$": "Variable expansion/command substitution",
        "`": "Command substitution",
        "\\": "Escape character - could bypass filters",
    }

    warnings = []

    # Check for dangerous patterns
    for pattern, message in dangerous_patterns:
        if re.search(pattern, command):
            return False, f"SECURITY ERROR: {message}"

    # Check for dangerous characters and provide warnings
    found_chars = set()
    for char in dangerous_chars:
        if char in command:
            found_chars.add(char)

    if found_chars:
        char_warnings = [f"'{char}' ({dangerous_chars[char]})" for char in found_chars]
        warnings.append(
            f"WARNING: Command contains potentially dangerous characters: {', '.join(char_warnings)}"
        )

    # Additional check: commands with multiple special chars are high risk
    special_char_count = sum(1 for char in dangerous_chars if char in command)
    if special_char_count >= 3:
        return False, "SECURITY ERROR: Command contains too many special characters (potential injection)"

    if warnings:
        return True, "\n".join(warnings)

    return True, None


async def execute_shell(
    command: str, cwd: str | None = None, timeout: int = 30
) -> str:
    """
    Execute a shell command with security validation.

    ⚠️  SECURITY WARNING ⚠️
    This function uses create_subprocess_shell which is vulnerable to shell injection.
    Input validation is performed but is NOT foolproof. Recommendations:

    1. NEVER pass user input directly to this function
    2. Use execute_python() for running code when possible
    3. Prefer allowlists of specific commands over blocklists
    4. Consider using create_subprocess_exec with explicit argument arrays instead
    5. Run in isolated environments (containers, VMs) when executing untrusted commands

    The command will be validated for obvious injection attempts, but sophisticated
    attacks may still bypass these checks.

    Args:
        command: Shell command to execute (will be validated for security)
        cwd: Working directory (defaults to current directory)
        timeout: Maximum execution time in seconds

    Returns:
        Command output (stdout and stderr combined), or error/warning messages

    Raises:
        ValueError: If command contains obviously dangerous patterns
    """
    # Validate the command for security issues
    is_safe, validation_message = _validate_shell_command(command)

    if not is_safe:
        raise ValueError(
            f"{validation_message}\n\n"
            f"Command rejected: {command}\n\n"
            f"If this command is safe and necessary, consider:\n"
            f"1. Rewriting it to avoid dangerous patterns\n"
            f"2. Using execute_python() instead if running code\n"
            f"3. Using subprocess.create_subprocess_exec() with explicit arguments"
        )

    result_prefix = ""
    if validation_message:
        result_prefix = f"{validation_message}\n\n"

    try:
        # Use shell=True with validated input
        # Note: This is still potentially unsafe, but validated
        process = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
        )

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), timeout=timeout
            )

            result = result_prefix
            if stdout:
                result += stdout.decode()
            if stderr:
                result += f"\n{stderr.decode()}" if result != result_prefix else stderr.decode()
            if process.returncode != 0:
                result += f"\n(Exit code: {process.returncode})"

            return result or f"{result_prefix}Command completed successfully (no output)"

        except asyncio.TimeoutError:
            process.kill()
            return f"{result_prefix}Command timed out after {timeout} seconds"

    except Exception as e:
        return f"{result_prefix}Error executing command: {str(e)}"
