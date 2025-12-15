"""
Code execution tools with sandbox support.
"""
import asyncio
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


async def execute_shell(
    command: str, cwd: str | None = None, timeout: int = 30
) -> str:
    """
    Execute a shell command.

    Args:
        command: Shell command to execute
        cwd: Working directory (defaults to current directory)
        timeout: Maximum execution time in seconds

    Returns:
        Command output (stdout and stderr combined)
    """
    try:
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

            result = ""
            if stdout:
                result += stdout.decode()
            if stderr:
                result += f"\n{stderr.decode()}" if result else stderr.decode()
            if process.returncode != 0:
                result += f"\n(Exit code: {process.returncode})"

            return result or "Command completed successfully (no output)"

        except asyncio.TimeoutError:
            process.kill()
            return f"Command timed out after {timeout} seconds"

    except Exception as e:
        return f"Error executing command: {str(e)}"
