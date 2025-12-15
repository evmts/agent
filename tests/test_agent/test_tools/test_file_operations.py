"""
Integration tests for file operation tools.
NO MOCKS - tests actual file system operations.
"""
import pytest
from pathlib import Path

from agent.tools.file_operations import (
    read_file,
    write_file,
    search_files,
    list_directory,
)


@pytest.fixture(autouse=True)
def setup_env(mock_env_vars):
    """Auto-use mock_env_vars for all tests in this module."""
    pass


class TestReadFile:
    """Test file reading functionality."""

    @pytest.mark.asyncio
    async def test_read_existing_file(self, temp_file):
        """Test reading an existing file."""
        result = await read_file(str(temp_file))

        assert "Hello, World!" in result
        assert "This is a test file." in result
        assert "Line 3" in result
        # Should include line numbers
        assert "1 |" in result or "   1 |" in result

    @pytest.mark.asyncio
    async def test_read_nonexistent_file(self):
        """Test reading a file that doesn't exist."""
        result = await read_file("/nonexistent/path/to/file.txt")

        assert "Error" in result or "not found" in result.lower()

    @pytest.mark.asyncio
    async def test_read_directory_not_file(self, temp_dir):
        """Test attempting to read a directory."""
        result = await read_file(str(temp_dir))

        assert "Error" in result or "Not a file" in result

    @pytest.mark.asyncio
    async def test_read_empty_file(self, temp_dir):
        """Test reading an empty file."""
        empty_file = temp_dir / "empty.txt"
        empty_file.write_text("")

        result = await read_file(str(empty_file))

        # Empty file should return empty or minimal output
        assert result is not None

    @pytest.mark.asyncio
    async def test_line_numbers_format(self, temp_file):
        """Test that line numbers are properly formatted."""
        result = await read_file(str(temp_file))

        # Check for line number formatting
        lines = result.split("\n")
        assert len(lines) >= 3
        # Each line should have a line number
        for line in lines[:3]:
            if line.strip():  # Skip empty lines
                assert "|" in line

    @pytest.mark.asyncio
    async def test_read_multiline_file(self, temp_dir):
        """Test reading a file with many lines."""
        multiline_file = temp_dir / "multiline.txt"
        content = "\n".join([f"Line {i}" for i in range(1, 101)])
        multiline_file.write_text(content)

        result = await read_file(str(multiline_file))

        assert "Line 1" in result
        assert "Line 100" in result

    @pytest.mark.asyncio
    async def test_read_with_special_characters(self, temp_dir):
        """Test reading a file with special characters."""
        special_file = temp_dir / "special.txt"
        special_file.write_text("Special chars: @#$%^&*()[]{}|\\<>?~`")

        result = await read_file(str(special_file))

        assert "@#$%^&*()" in result


class TestWriteFile:
    """Test file writing functionality."""

    @pytest.mark.asyncio
    async def test_write_new_file(self, temp_dir):
        """Test writing to a new file."""
        new_file = temp_dir / "new_file.txt"
        content = "This is new content"

        result = await write_file(str(new_file), content)

        assert "Successfully wrote" in result
        assert new_file.exists()
        assert new_file.read_text() == content

    @pytest.mark.asyncio
    async def test_overwrite_existing_file(self, temp_file):
        """Test overwriting an existing file."""
        new_content = "Overwritten content"

        result = await write_file(str(temp_file), new_content)

        assert "Successfully wrote" in result
        assert temp_file.read_text() == new_content

    @pytest.mark.asyncio
    async def test_write_creates_parent_directories(self, temp_dir):
        """Test that write_file creates parent directories."""
        nested_file = temp_dir / "nested" / "deep" / "file.txt"
        content = "Nested content"

        result = await write_file(str(nested_file), content)

        assert "Successfully wrote" in result
        assert nested_file.exists()
        assert nested_file.read_text() == content

    @pytest.mark.asyncio
    async def test_write_empty_content(self, temp_dir):
        """Test writing empty content to a file."""
        empty_file = temp_dir / "empty.txt"

        result = await write_file(str(empty_file), "")

        assert "Successfully wrote" in result
        assert empty_file.exists()
        assert empty_file.read_text() == ""

    @pytest.mark.asyncio
    async def test_write_multiline_content(self, temp_dir):
        """Test writing multiline content."""
        multiline_file = temp_dir / "multiline.txt"
        content = "Line 1\nLine 2\nLine 3\n"

        result = await write_file(str(multiline_file), content)

        assert "Successfully wrote" in result
        assert multiline_file.read_text() == content

    @pytest.mark.asyncio
    async def test_write_special_characters(self, temp_dir):
        """Test writing special characters."""
        special_file = temp_dir / "special.txt"
        content = "Special: @#$%^&*()[]{}|\\<>?~`\n"

        result = await write_file(str(special_file), content)

        assert "Successfully wrote" in result
        assert special_file.read_text() == content

    @pytest.mark.asyncio
    async def test_write_unicode_content(self, temp_dir):
        """Test writing Unicode content."""
        unicode_file = temp_dir / "unicode.txt"
        content = "Hello 世界 🌍 Привет"

        result = await write_file(str(unicode_file), content)

        assert "Successfully wrote" in result
        assert unicode_file.read_text() == content


class TestSearchFiles:
    """Test file searching functionality."""

    @pytest.mark.asyncio
    async def test_search_by_extension(self, temp_dir):
        """Test searching files by extension."""
        # Create test files
        (temp_dir / "test1.py").write_text("print('test1')")
        (temp_dir / "test2.py").write_text("print('test2')")
        (temp_dir / "test3.txt").write_text("text file")

        result = await search_files("*.py", str(temp_dir))

        assert "test1.py" in result
        assert "test2.py" in result
        assert "test3.txt" not in result

    @pytest.mark.asyncio
    async def test_search_recursive(self, temp_dir):
        """Test recursive file search."""
        # Create nested structure
        nested_dir = temp_dir / "nested" / "deep"
        nested_dir.mkdir(parents=True)
        (nested_dir / "deep_file.py").write_text("deep file")
        (temp_dir / "root_file.py").write_text("root file")

        result = await search_files("**/*.py", str(temp_dir))

        assert "deep_file.py" in result
        assert "root_file.py" in result

    @pytest.mark.asyncio
    async def test_search_with_content_filter(self, temp_dir):
        """Test searching files with content pattern."""
        # Create files with different content
        (temp_dir / "has_pattern.py").write_text("def my_function():\n    pass")
        (temp_dir / "no_pattern.py").write_text("x = 1 + 1")

        result = await search_files(
            "*.py", str(temp_dir), content_pattern="def.*function"
        )

        assert "has_pattern.py" in result
        assert "no_pattern.py" not in result

    @pytest.mark.asyncio
    async def test_search_no_matches(self, temp_dir):
        """Test search with no matching files."""
        (temp_dir / "test.txt").write_text("content")

        result = await search_files("*.py", str(temp_dir))

        assert "No files found" in result

    @pytest.mark.asyncio
    async def test_search_max_results(self, temp_dir):
        """Test that max_results limits output."""
        # Create many files
        for i in range(100):
            (temp_dir / f"file{i}.txt").write_text(f"content {i}")

        result = await search_files("*.txt", str(temp_dir), max_results=10)

        # Should find at most 10 files (the header line says "Found 10 files:")
        # Count actual file entries, not the header
        lines = result.split("\n")
        # First line is "Found X files:", rest are file names
        file_lines = [line for line in lines[1:] if line.strip()]
        assert len(file_lines) == 10

    @pytest.mark.asyncio
    async def test_search_nonexistent_directory(self):
        """Test searching in a nonexistent directory."""
        result = await search_files("*.py", "/nonexistent/directory/path")

        # Should return an error message
        assert "Error" in result or "not found" in result.lower()


class TestListDirectory:
    """Test directory listing functionality."""

    @pytest.mark.asyncio
    async def test_list_directory(self, temp_dir):
        """Test listing a directory."""
        # Create some files and subdirectories
        (temp_dir / "file1.txt").write_text("content")
        (temp_dir / "file2.py").write_text("code")
        (temp_dir / "subdir").mkdir()

        result = await list_directory(str(temp_dir))

        assert "file1.txt" in result
        assert "file2.py" in result
        assert "subdir" in result

    @pytest.mark.asyncio
    async def test_list_shows_file_types(self, temp_dir):
        """Test that listing shows file types."""
        (temp_dir / "file.txt").write_text("content")
        (temp_dir / "directory").mkdir()

        result = await list_directory(str(temp_dir))

        assert "[FILE]" in result
        assert "[DIR]" in result

    @pytest.mark.asyncio
    async def test_list_shows_sizes(self, temp_dir):
        """Test that listing shows file sizes."""
        (temp_dir / "file.txt").write_text("content with some length")

        result = await list_directory(str(temp_dir))

        # Should show size in some format (B, KB, MB, etc.)
        assert "B)" in result or "KB)" in result

    @pytest.mark.asyncio
    async def test_list_hidden_files(self, temp_dir):
        """Test listing with/without hidden files."""
        (temp_dir / "visible.txt").write_text("visible")
        (temp_dir / ".hidden.txt").write_text("hidden")

        # Without hidden files
        result_no_hidden = await list_directory(str(temp_dir), include_hidden=False)
        assert "visible.txt" in result_no_hidden
        assert ".hidden.txt" not in result_no_hidden

        # With hidden files
        result_with_hidden = await list_directory(str(temp_dir), include_hidden=True)
        assert "visible.txt" in result_with_hidden
        assert ".hidden.txt" in result_with_hidden

    @pytest.mark.asyncio
    async def test_list_empty_directory(self, temp_dir):
        """Test listing an empty directory."""
        empty_dir = temp_dir / "empty"
        empty_dir.mkdir()

        result = await list_directory(str(empty_dir))

        assert "empty" in result.lower()

    @pytest.mark.asyncio
    async def test_list_nonexistent_directory(self):
        """Test listing a nonexistent directory."""
        result = await list_directory("/nonexistent/directory/path")

        assert "Error" in result or "not found" in result.lower()

    @pytest.mark.asyncio
    async def test_list_file_not_directory(self, temp_file):
        """Test attempting to list a file instead of directory."""
        result = await list_directory(str(temp_file))

        assert "Error" in result or "Not a directory" in result

    @pytest.mark.asyncio
    async def test_list_sorts_entries(self, temp_dir):
        """Test that directory listing is sorted."""
        # Create files in non-alphabetical order
        (temp_dir / "zebra.txt").write_text("z")
        (temp_dir / "apple.txt").write_text("a")
        (temp_dir / "middle.txt").write_text("m")

        result = await list_directory(str(temp_dir))

        # Check that they appear in sorted order
        apple_pos = result.index("apple.txt")
        middle_pos = result.index("middle.txt")
        zebra_pos = result.index("zebra.txt")

        assert apple_pos < middle_pos < zebra_pos
