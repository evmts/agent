#!/usr/bin/env python3
"""
Integration test for custom slash commands.

Tests command loading, expansion, and API endpoints.
"""

import tempfile
from pathlib import Path

from config.commands import CommandRegistry, CustomCommand


def test_command_loading():
    """Test loading commands from markdown files."""
    print("Testing command loading...")

    with tempfile.TemporaryDirectory() as tmpdir:
        prompts_dir = Path(tmpdir) / "prompts"
        prompts_dir.mkdir()

        # Create a test command file
        cmd_file = prompts_dir / "test-cmd.md"
        cmd_file.write_text("""---
name: test-cmd
description: A test command
args:
  - name: arg1
    required: true
    description: First argument
  - name: arg2
    default: default_value
---

This is a test command with {{arg1}} and {{arg2}}.
""")

        # Load commands
        registry = CommandRegistry(prompts_dir)
        registry.load_commands()

        # Verify command was loaded
        commands = registry.list_commands()
        assert len(commands) == 1
        assert commands[0].name == "test-cmd"
        assert commands[0].description == "A test command"

        print("✓ Command loading works")


def test_command_expansion():
    """Test command template expansion."""
    print("Testing command expansion...")

    with tempfile.TemporaryDirectory() as tmpdir:
        prompts_dir = Path(tmpdir) / "prompts"
        prompts_dir.mkdir()

        # Create command with positional args
        cmd_file1 = prompts_dir / "positional.md"
        cmd_file1.write_text("This is $1 and $2.")

        # Create command with named args
        cmd_file2 = prompts_dir / "named.md"
        cmd_file2.write_text("""---
name: named
args:
  - name: name
    required: true
  - name: type
    default: feature
---

Add {{type}}: {{name}}
""")

        registry = CommandRegistry(prompts_dir)
        registry.load_commands()

        # Test positional expansion
        expanded = registry.expand_command("positional", args=["foo", "bar"])
        assert expanded == "This is foo and bar."

        # Test named expansion
        expanded = registry.expand_command("named", kwargs={"name": "test"})
        assert expanded == "Add feature: test"

        # Test named expansion with override
        expanded = registry.expand_command("named", kwargs={"name": "test", "type": "fix"})
        assert expanded == "Add fix: test"

        # Test positional args for named template
        expanded = registry.expand_command("named", args=["test", "docs"])
        assert expanded == "Add docs: test"

        print("✓ Command expansion works")


def test_required_args():
    """Test that required arguments are validated."""
    print("Testing required argument validation...")

    with tempfile.TemporaryDirectory() as tmpdir:
        prompts_dir = Path(tmpdir) / "prompts"
        prompts_dir.mkdir()

        # Create command with required arg
        cmd_file = prompts_dir / "required.md"
        cmd_file.write_text("""---
args:
  - name: required_arg
    required: true
---

Value: {{required_arg}}
""")

        registry = CommandRegistry(prompts_dir)
        registry.load_commands()

        # Should raise ValueError for missing required arg
        try:
            registry.expand_command("required")
            assert False, "Should have raised ValueError"
        except ValueError as e:
            assert "required_arg" in str(e)

        print("✓ Required argument validation works")


def test_lazy_loading():
    """Test that commands are loaded lazily."""
    print("Testing lazy loading...")

    with tempfile.TemporaryDirectory() as tmpdir:
        prompts_dir = Path(tmpdir) / "prompts"
        prompts_dir.mkdir()

        # Create a test command
        cmd_file = prompts_dir / "lazy.md"
        cmd_file.write_text("Lazy loaded command")

        # Create registry but don't call load_commands
        registry = CommandRegistry(prompts_dir)

        # Commands should be loaded on first access
        commands = registry.list_commands()
        assert len(commands) == 1
        assert commands[0].name == "lazy"

        print("✓ Lazy loading works")


def test_reload():
    """Test reloading commands from disk."""
    print("Testing command reload...")

    with tempfile.TemporaryDirectory() as tmpdir:
        prompts_dir = Path(tmpdir) / "prompts"
        prompts_dir.mkdir()

        # Create initial command
        cmd_file = prompts_dir / "reload-test.md"
        cmd_file.write_text("Initial content")

        registry = CommandRegistry(prompts_dir)
        registry.load_commands()

        # Verify initial state
        cmd = registry.get_command("reload-test")
        assert cmd.template == "Initial content"

        # Modify the file
        cmd_file.write_text("Updated content")

        # Reload
        registry.reload()

        # Verify updated content
        cmd = registry.get_command("reload-test")
        assert cmd.template == "Updated content"

        print("✓ Command reload works")


def main():
    """Run all tests."""
    print("=" * 60)
    print("Custom Slash Commands Integration Test")
    print("=" * 60)
    print()

    tests = [
        test_command_loading,
        test_command_expansion,
        test_required_args,
        test_lazy_loading,
        test_reload,
    ]

    for test in tests:
        try:
            test()
        except Exception as e:
            print(f"✗ Test failed: {e}")
            import traceback
            traceback.print_exc()
            return 1

    print()
    print("=" * 60)
    print("All tests passed!")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    exit(main())
