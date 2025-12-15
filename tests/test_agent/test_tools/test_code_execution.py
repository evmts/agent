"""
Integration tests for code execution tools.
NO MOCKS - tests actual code execution.
"""
import asyncio

import pytest

from agent.tools.code_execution import execute_python, execute_shell


class TestExecutePython:
    """Test Python code execution."""

    @pytest.mark.asyncio
    async def test_simple_print(self):
        """Test executing Python code with print statements."""
        code = """
print("Hello, World!")
print("Line 2")
"""
        result = await execute_python(code)

        assert "STDOUT:" in result
        assert "Hello, World!" in result
        assert "Line 2" in result

    @pytest.mark.asyncio
    async def test_return_value_not_captured(self):
        """Test that return values are not captured (only print output)."""
        code = """
result = 42 + 8
print(f"Result: {result}")
"""
        result = await execute_python(code)

        assert "Result: 50" in result

    @pytest.mark.asyncio
    async def test_error_handling(self):
        """Test Python code with errors."""
        code = """
print("Before error")
raise ValueError("Test error")
print("After error")
"""
        result = await execute_python(code)

        assert "Before error" in result
        assert "ValueError: Test error" in result
        assert "Exit code: 1" in result
        assert "After error" not in result

    @pytest.mark.asyncio
    async def test_syntax_error(self):
        """Test Python code with syntax errors."""
        code = """
def bad_function(
    print("missing closing paren")
"""
        result = await execute_python(code)

        assert "STDERR:" in result
        assert "SyntaxError" in result or "IndentationError" in result

    @pytest.mark.asyncio
    async def test_timeout(self):
        """Test execution timeout."""
        code = """
import time
time.sleep(10)
print("This should not print")
"""
        result = await execute_python(code, timeout=1)

        assert "timed out" in result.lower()

    @pytest.mark.asyncio
    async def test_no_output(self):
        """Test code that executes successfully but produces no output."""
        code = """
x = 1 + 1
y = x * 2
"""
        result = await execute_python(code)

        assert "successfully" in result.lower() or result == ""

    @pytest.mark.asyncio
    async def test_imports_and_calculations(self):
        """Test code with imports and calculations."""
        code = """
import math
result = math.sqrt(16)
print(f"Square root of 16 is {result}")
"""
        result = await execute_python(code)

        assert "Square root of 16 is 4.0" in result

    @pytest.mark.asyncio
    async def test_multiline_output(self):
        """Test code with multiple lines of output."""
        code = """
for i in range(5):
    print(f"Line {i}")
"""
        result = await execute_python(code)

        assert "Line 0" in result
        assert "Line 4" in result

    @pytest.mark.asyncio
    async def test_stderr_output(self):
        """Test code that writes to stderr."""
        code = """
import sys
sys.stderr.write("Error message\\n")
print("Normal output")
"""
        result = await execute_python(code)

        assert "STDOUT:" in result
        assert "STDERR:" in result
        assert "Normal output" in result
        assert "Error message" in result


class TestExecuteShell:
    """Test shell command execution."""

    @pytest.mark.asyncio
    async def test_simple_echo(self):
        """Test simple echo command."""
        result = await execute_shell("echo 'Hello, Shell!'")

        assert "Hello, Shell!" in result

    @pytest.mark.asyncio
    async def test_pwd_command(self):
        """Test pwd command returns current directory."""
        result = await execute_shell("pwd")

        assert "/" in result  # Should contain path separator
        assert len(result) > 1

    @pytest.mark.asyncio
    async def test_ls_command(self):
        """Test ls command."""
        result = await execute_shell("ls -la")

        # Should list current directory
        assert result.strip() != ""

    @pytest.mark.asyncio
    async def test_pipe_commands(self):
        """Test piped shell commands."""
        result = await execute_shell("echo 'test' | tr 'a-z' 'A-Z'")

        assert "TEST" in result

    @pytest.mark.asyncio
    async def test_working_directory(self, temp_dir):
        """Test command execution in specific working directory."""
        # Create a test file in temp_dir
        test_file = temp_dir / "marker.txt"
        test_file.write_text("marker")

        result = await execute_shell("ls", cwd=str(temp_dir))

        assert "marker.txt" in result

    @pytest.mark.asyncio
    async def test_command_with_error(self):
        """Test command that returns non-zero exit code."""
        result = await execute_shell("ls /nonexistent_directory_12345")

        assert "Exit code:" in result or "cannot access" in result.lower() or "no such file" in result.lower()

    @pytest.mark.asyncio
    async def test_timeout(self):
        """Test command timeout."""
        result = await execute_shell("sleep 10", timeout=1)

        assert "timed out" in result.lower()

    @pytest.mark.asyncio
    async def test_multiline_output(self):
        """Test command with multiline output."""
        result = await execute_shell("printf 'Line 1\\nLine 2\\nLine 3'")

        assert "Line 1" in result
        assert "Line 2" in result
        assert "Line 3" in result

    @pytest.mark.asyncio
    async def test_environment_variables(self):
        """Test command using environment variables."""
        result = await execute_shell("echo $HOME")

        # HOME should be set in the environment
        assert result.strip() != "$HOME"  # Should be expanded

    @pytest.mark.asyncio
    async def test_invalid_command(self):
        """Test executing invalid/nonexistent command."""
        result = await execute_shell("nonexistent_command_xyz123")

        assert "not found" in result.lower() or "error" in result.lower()

    @pytest.mark.asyncio
    async def test_python_via_shell(self):
        """Test executing Python via shell."""
        result = await execute_shell("python3 -c 'print(2 + 2)'")

        assert "4" in result
