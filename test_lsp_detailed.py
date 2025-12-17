#!/usr/bin/env python3
"""
Detailed LSP integration test with better timeout handling and debugging.
"""

import asyncio
import sys
import tempfile
from pathlib import Path

# Add agent directory to path
AGENT_DIR = Path(__file__).parent / "agent"
sys.path.insert(0, str(AGENT_DIR.parent))

from agent.tools import lsp

print("=" * 80)
print("DETAILED LSP INTEGRATION TEST")
print("=" * 80)
print()

async def test_hover_detailed():
    """Test hover with detailed logging and longer timeout."""
    try:
        # Temporarily increase timeout for this test
        original_timeout = lsp.LSP_REQUEST_TIMEOUT_SECONDS
        lsp.LSP_REQUEST_TIMEOUT_SECONDS = 10.0

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
            print()

            # Test 1: Hover on function name
            print("Test 1: Hover on 'add_numbers' function name (line 1, char 4)")
            print("-" * 40)
            result = await lsp.hover(str(test_file), line=1, character=4)

            print(f"Success: {result.get('success')}")
            if result.get('success'):
                print(f"Contents:\n{result.get('contents')}\n")
                if result.get('range'):
                    print(f"Range: {result.get('range')}")
                print(f"Language: {result.get('language')}")
            else:
                print(f"Error: {result.get('error')}")
            print()

            # Test 2: Hover on parameter type annotation
            print("Test 2: Hover on 'int' type annotation (line 1, char 21)")
            print("-" * 40)
            result2 = await lsp.hover(str(test_file), line=1, character=21)

            print(f"Success: {result2.get('success')}")
            if result2.get('success'):
                print(f"Contents:\n{result2.get('contents')}\n")
            else:
                print(f"Error: {result2.get('error')}")
            print()

            # Test 3: Hover on function call
            print("Test 3: Hover on 'add_numbers' function call (line 5, char 9)")
            print("-" * 40)
            result3 = await lsp.hover(str(test_file), line=5, character=9)

            print(f"Success: {result3.get('success')}")
            if result3.get('success'):
                print(f"Contents:\n{result3.get('contents')}\n")
            else:
                print(f"Error: {result3.get('error')}")
            print()

            # Cleanup: shutdown all LSP clients
            print("Shutting down LSP clients...")
            manager = await lsp.get_lsp_manager()
            await manager.shutdown_all()
            print("✓ LSP clients shut down successfully")

        # Restore original timeout
        lsp.LSP_REQUEST_TIMEOUT_SECONDS = original_timeout

    except Exception as e:
        print(f"✗ Test failed with exception: {e}")
        import traceback
        traceback.print_exc()
        return False

    return True

try:
    success = asyncio.run(test_hover_detailed())
    print()
    print("=" * 80)
    if success:
        print("TEST COMPLETED")
    else:
        print("TEST FAILED")
    print("=" * 80)
except Exception as e:
    print(f"\n✗ Failed to run test: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
