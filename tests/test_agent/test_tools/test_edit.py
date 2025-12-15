"""
Integration tests for file editing tools.
NO MOCKS - tests actual file system operations.
"""
import pytest
from pathlib import Path

from agent.tools.edit import edit_file, patch_file


@pytest.fixture(autouse=True)
def setup_env(mock_env_vars):
    """Auto-use mock_env_vars for all tests in this module."""
    pass


class TestEditFile:
    """Test edit_file functionality."""

    @pytest.mark.asyncio
    async def test_edit_single_occurrence(self, temp_dir):
        """Test replacing a single occurrence."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("Hello World\nThis is a test\nGoodbye World")

        result = await edit_file(str(test_file), "Hello World", "Hi Universe")

        assert "Successfully replaced 1 occurrence" in result
        content = test_file.read_text()
        assert content == "Hi Universe\nThis is a test\nGoodbye World"

    @pytest.mark.asyncio
    async def test_edit_multiple_occurrences_error(self, temp_dir):
        """Test that multiple occurrences without replace_all errors."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("foo\nbar\nfoo\nbaz")

        result = await edit_file(str(test_file), "foo", "qux")

        assert "Error" in result
        assert "Found 2 occurrences" in result
        # File should not be modified
        assert test_file.read_text() == "foo\nbar\nfoo\nbaz"

    @pytest.mark.asyncio
    async def test_edit_replace_all(self, temp_dir):
        """Test replacing all occurrences with replace_all=True."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("foo\nbar\nfoo\nbaz")

        result = await edit_file(str(test_file), "foo", "qux", replace_all=True)

        assert "Successfully replaced all 2 occurrences" in result
        content = test_file.read_text()
        assert content == "qux\nbar\nqux\nbaz"

    @pytest.mark.asyncio
    async def test_edit_string_not_found(self, temp_dir):
        """Test error when old_string is not found."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("Hello World")

        result = await edit_file(str(test_file), "Not Found", "Something")

        assert "Error" in result
        assert "not found" in result
        # File should not be modified
        assert test_file.read_text() == "Hello World"

    @pytest.mark.asyncio
    async def test_edit_same_strings(self, temp_dir):
        """Test error when old_string and new_string are the same."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("Hello World")

        result = await edit_file(str(test_file), "Hello", "Hello")

        assert "Error" in result
        assert "must be different" in result

    @pytest.mark.asyncio
    async def test_edit_nonexistent_file(self):
        """Test error when file doesn't exist."""
        result = await edit_file("/nonexistent/file.txt", "old", "new")

        assert "Error" in result
        assert "not found" in result.lower()

    @pytest.mark.asyncio
    async def test_edit_multiline_string(self, temp_dir):
        """Test editing multiline strings."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("def foo():\n    pass\n\nbar()")

        result = await edit_file(
            str(test_file),
            "def foo():\n    pass",
            "def foo():\n    return 42"
        )

        assert "Successfully replaced 1 occurrence" in result
        content = test_file.read_text()
        assert "return 42" in content
        assert "pass" not in content

    @pytest.mark.asyncio
    async def test_edit_with_special_characters(self, temp_dir):
        """Test editing strings with special characters."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("price: $100\ntotal: $200")

        result = await edit_file(str(test_file), "$100", "$150")

        assert "Successfully replaced 1 occurrence" in result
        content = test_file.read_text()
        assert "$150" in content
        assert "$100" not in content

    @pytest.mark.asyncio
    async def test_edit_empty_file(self, temp_dir):
        """Test editing an empty file."""
        test_file = temp_dir / "empty.txt"
        test_file.write_text("")

        result = await edit_file(str(test_file), "old", "new")

        assert "Error" in result
        assert "not found" in result


class TestPatchFile:
    """Test patch_file functionality."""

    @pytest.mark.asyncio
    async def test_patch_simple_change(self, temp_dir):
        """Test applying a simple patch."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("line 1\nline 2\nline 3")

        patch = """--- test.txt
+++ test.txt
@@ -1,3 +1,3 @@
 line 1
-line 2
+modified line 2
 line 3"""

        result = await patch_file(str(test_file), patch)

        assert "Successfully applied patch" in result
        content = test_file.read_text()
        assert content == "line 1\nmodified line 2\nline 3"

    @pytest.mark.asyncio
    async def test_patch_add_lines(self, temp_dir):
        """Test applying a patch that adds lines."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("line 1\nline 3")

        patch = """--- test.txt
+++ test.txt
@@ -1,2 +1,3 @@
 line 1
+line 2
 line 3"""

        result = await patch_file(str(test_file), patch)

        assert "Successfully applied patch" in result
        content = test_file.read_text()
        assert content == "line 1\nline 2\nline 3"

    @pytest.mark.asyncio
    async def test_patch_remove_lines(self, temp_dir):
        """Test applying a patch that removes lines."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("line 1\nline 2\nline 3")

        patch = """--- test.txt
+++ test.txt
@@ -1,3 +1,2 @@
 line 1
-line 2
 line 3"""

        result = await patch_file(str(test_file), patch)

        assert "Successfully applied patch" in result
        content = test_file.read_text()
        assert content == "line 1\nline 3"

    @pytest.mark.asyncio
    async def test_patch_mismatch_error(self, temp_dir):
        """Test error when patch doesn't match file."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("line 1\nwrong line\nline 3")

        patch = """--- test.txt
+++ test.txt
@@ -1,3 +1,3 @@
 line 1
-line 2
+modified line 2
 line 3"""

        result = await patch_file(str(test_file), patch)

        assert "Error" in result
        assert "does not match" in result
        # File should not be modified
        assert test_file.read_text() == "line 1\nwrong line\nline 3"

    @pytest.mark.asyncio
    async def test_patch_nonexistent_file(self):
        """Test error when file doesn't exist."""
        patch = """--- test.txt
+++ test.txt
@@ -1,1 +1,1 @@
-old
+new"""

        result = await patch_file("/nonexistent/file.txt", patch)

        assert "Error" in result
        assert "not found" in result.lower()

    @pytest.mark.asyncio
    async def test_patch_invalid_format(self, temp_dir):
        """Test error with invalid patch format."""
        test_file = temp_dir / "test.txt"
        test_file.write_text("line 1\nline 2")

        patch = "This is not a valid unified diff"

        result = await patch_file(str(test_file), patch)

        assert "Error" in result
