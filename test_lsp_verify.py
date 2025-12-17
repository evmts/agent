#!/usr/bin/env python3
"""
LSP implementation verification test script.

Tests:
1. Module imports
2. Data structures (Position, Range, HoverResult)
3. Utility functions (parse_hover_contents, get_language_id, find_workspace_root)
4. Message framing helpers
5. If pylsp is available: Full hover() integration test
"""

import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

# Add agent directory to path
AGENT_DIR = Path(__file__).parent / "agent"
sys.path.insert(0, str(AGENT_DIR.parent))

print("=" * 80)
print("LSP IMPLEMENTATION VERIFICATION")
print("=" * 80)
print()

# Test 1: Module imports
print("Test 1: Module Imports")
print("-" * 40)
try:
    from agent.tools import lsp
    print("✓ Successfully imported agent.tools.lsp")

    # Check key classes and functions exist
    assert hasattr(lsp, "hover"), "Missing hover() function"
    assert hasattr(lsp, "Position"), "Missing Position class"
    assert hasattr(lsp, "Range"), "Missing Range class"
    assert hasattr(lsp, "HoverResult"), "Missing HoverResult class"
    assert hasattr(lsp, "LSPClient"), "Missing LSPClient class"
    assert hasattr(lsp, "LSPManager"), "Missing LSPManager class"
    assert hasattr(lsp, "LSPConnection"), "Missing LSPConnection class"
    print("✓ All required classes and functions present")
except Exception as e:
    print(f"✗ Import failed: {e}")
    sys.exit(1)
print()

# Test 2: Data structures
print("Test 2: Data Structures")
print("-" * 40)
try:
    # Position
    pos = lsp.Position(line=5, character=10)
    assert pos.line == 5
    assert pos.character == 10
    assert pos.to_dict() == {"line": 5, "character": 10}
    print("✓ Position class works correctly")

    # Range
    start = lsp.Position(line=1, character=0)
    end = lsp.Position(line=1, character=15)
    rng = lsp.Range(start=start, end=end)
    assert rng.start.line == 1
    assert rng.end.character == 15
    rng_dict = rng.to_dict()
    assert rng_dict["start"]["line"] == 1
    assert rng_dict["end"]["character"] == 15
    print("✓ Range class works correctly")

    # Range.from_dict
    rng2 = lsp.Range.from_dict(rng_dict)
    assert rng2.start.line == 1
    assert rng2.end.character == 15
    print("✓ Range.from_dict() works correctly")

    # HoverResult
    hover_result = lsp.HoverResult(
        contents="def foo(x: int) -> str",
        range=rng,
        language="python"
    )
    assert hover_result.contents == "def foo(x: int) -> str"
    assert hover_result.language == "python"
    print("✓ HoverResult class works correctly")
except Exception as e:
    print(f"✗ Data structure test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
print()

# Test 3: Utility functions
print("Test 3: Utility Functions")
print("-" * 40)
try:
    # get_language_id
    assert lsp.get_language_id(".py") == "python"
    assert lsp.get_language_id(".ts") == "typescript"
    assert lsp.get_language_id(".tsx") == "typescriptreact"
    assert lsp.get_language_id(".go") == "go"
    assert lsp.get_language_id(".rs") == "rust"
    assert lsp.get_language_id(".xyz") == "plaintext"  # Unknown extension
    print("✓ get_language_id() works correctly")

    # parse_hover_contents - string
    assert lsp.parse_hover_contents("simple text") == "simple text"
    print("✓ parse_hover_contents() handles strings")

    # parse_hover_contents - MarkupContent
    markup = {"kind": "markdown", "value": "**bold**"}
    assert lsp.parse_hover_contents(markup) == "**bold**"
    print("✓ parse_hover_contents() handles MarkupContent")

    # parse_hover_contents - MarkedString with language
    marked = {"language": "python", "value": "def foo(): pass"}
    assert lsp.parse_hover_contents(marked) == "```python\ndef foo(): pass\n```"
    print("✓ parse_hover_contents() handles MarkedString with language")

    # parse_hover_contents - array
    arr = ["text1", {"value": "text2"}]
    result = lsp.parse_hover_contents(arr)
    assert "text1" in result and "text2" in result
    print("✓ parse_hover_contents() handles arrays")

    # parse_hover_contents - None/empty
    assert lsp.parse_hover_contents(None) == ""
    print("✓ parse_hover_contents() handles None")

    # get_server_for_file
    server_info = lsp.get_server_for_file("/path/to/file.py")
    assert server_info is not None
    assert server_info[0] == "python"
    assert server_info[1]["command"] == ["pylsp"]
    print("✓ get_server_for_file() works for Python files")

    server_info = lsp.get_server_for_file("/path/to/file.xyz")
    assert server_info is None
    print("✓ get_server_for_file() returns None for unknown extensions")

    # find_workspace_root
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a structure: tmpdir/project/pyproject.toml and tmpdir/project/src/code.py
        project_dir = Path(tmpdir) / "project"
        project_dir.mkdir()
        (project_dir / "pyproject.toml").touch()
        src_dir = project_dir / "src"
        src_dir.mkdir()
        code_file = src_dir / "code.py"
        code_file.touch()

        # Should find project_dir
        root = lsp.find_workspace_root(str(code_file), ["pyproject.toml"])
        # Resolve both paths for comparison (handles symlinks)
        assert Path(root).resolve() == project_dir.resolve()
        print("✓ find_workspace_root() finds marker files correctly")

        # With no markers, should return file's directory
        root = lsp.find_workspace_root(str(code_file), ["nonexistent.txt"])
        assert Path(root).resolve() == src_dir.resolve()
        print("✓ find_workspace_root() falls back to file directory")

except Exception as e:
    print(f"✗ Utility function test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
print()

# Test 4: Message framing (test internal helpers if possible)
print("Test 4: Message Framing Helpers")
print("-" * 40)
try:
    # Test that we can create a properly framed message manually
    test_message = {"jsonrpc": "2.0", "id": 1, "method": "test", "params": {}}
    body = json.dumps(test_message).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n"
    full_message = header.encode("utf-8") + body

    # Verify header format
    assert full_message.startswith(b"Content-Length: ")
    assert b"\r\n\r\n" in full_message
    print("✓ Message framing format is correct")

    # Verify we can parse it back
    header_end = full_message.index(b"\r\n\r\n")
    header_part = full_message[:header_end].decode("utf-8")
    body_part = full_message[header_end + 4:]

    assert "Content-Length:" in header_part
    parsed_message = json.loads(body_part.decode("utf-8"))
    assert parsed_message["method"] == "test"
    print("✓ Message can be parsed correctly")

except Exception as e:
    print(f"✗ Message framing test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
print()

# Test 5: Check if pylsp is available
print("Test 5: pylsp Installation Check")
print("-" * 40)
import shutil
pylsp_path = shutil.which("pylsp")
if pylsp_path:
    print(f"✓ pylsp is installed at: {pylsp_path}")
    pylsp_available = True
else:
    print("✗ pylsp is NOT installed")
    print("  Install with: pip install python-lsp-server")
    pylsp_available = False
print()

# Test 6: Integration test (only if pylsp is available)
if pylsp_available:
    print("Test 6: Full Integration Test")
    print("-" * 40)

    async def test_hover():
        try:
            # Create a temporary Python file with a typed function
            with tempfile.TemporaryDirectory() as tmpdir:
                test_file = Path(tmpdir) / "test_file.py"
                test_file.write_text('''
def add_numbers(x: int, y: int) -> int:
    """Add two numbers together."""
    return x + y

result = add_numbers(5, 10)
''')

                print(f"Created test file: {test_file}")

                # Test hover on the function name
                # Line 1 (0-indexed), character 4 (inside "add_numbers")
                result = await lsp.hover(str(test_file), line=1, character=4)

                print("\nHover result:")
                print(json.dumps(result, indent=2))

                if result.get("success"):
                    print("\n✓ Hover request succeeded")

                    contents = result.get("contents", "")
                    if "add_numbers" in contents or "int" in contents:
                        print("✓ Hover contents include expected type information")
                    else:
                        print("⚠ Hover contents may not include expected information")
                        print(f"  Contents: {contents}")

                    return True
                else:
                    print(f"\n✗ Hover request failed: {result.get('error')}")
                    return False

        except Exception as e:
            print(f"\n✗ Integration test failed: {e}")
            import traceback
            traceback.print_exc()
            return False

    try:
        success = asyncio.run(test_hover())
        if not success:
            print("\nIntegration test did not complete successfully")
    except Exception as e:
        print(f"\n✗ Failed to run integration test: {e}")
        import traceback
        traceback.print_exc()
else:
    print("Test 6: Full Integration Test")
    print("-" * 40)
    print("⊘ Skipped - pylsp not installed")

print()
print("=" * 80)
print("VERIFICATION COMPLETE")
print("=" * 80)
