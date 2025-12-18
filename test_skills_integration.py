#!/usr/bin/env python3
"""Test script for skills system integration."""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from config.skills import get_skill_registry, expand_skill_references


def test_skill_loading():
    """Test that skills are loaded from ~/.agent/skills/"""
    print("Testing skill loading...")
    registry = get_skill_registry()
    registry.load_skills()

    skills = registry.list_skills()
    print(f"✓ Loaded {len(skills)} skills:")
    for skill in skills:
        print(f"  - {skill.name}: {skill.description}")

    return len(skills) > 0


def test_skill_retrieval():
    """Test retrieving a specific skill."""
    print("\nTesting skill retrieval...")
    registry = get_skill_registry()

    # Try to get an existing skill
    skill = registry.get_skill("python-best-practices")
    if skill:
        print(f"✓ Retrieved skill: {skill.name}")
        print(f"  Description: {skill.description}")
        print(f"  Content length: {len(skill.content)} chars")
        return True
    else:
        print("✗ Could not retrieve skill 'python-best-practices'")
        return False


def test_skill_search():
    """Test searching for skills."""
    print("\nTesting skill search...")
    registry = get_skill_registry()

    results = registry.search_skills("python")
    print(f"✓ Found {len(results)} skills matching 'python':")
    for skill in results:
        print(f"  - {skill.name}")

    return len(results) > 0


def test_skill_expansion():
    """Test expanding skill references in text."""
    print("\nTesting skill reference expansion...")

    # Test with valid skill reference
    message = "Please help me write code following $python-best-practices"
    expanded, skills_used = expand_skill_references(message)

    if skills_used and "python-best-practices" in skills_used:
        print(f"✓ Expanded skill reference: {skills_used}")
        print(f"  Original length: {len(message)} chars")
        print(f"  Expanded length: {len(expanded)} chars")
        print(f"  Expansion includes skill content: {len(expanded) > len(message)}")
        return True
    else:
        print("✗ Failed to expand skill reference")
        return False


def test_multiple_skills():
    """Test expanding multiple skill references."""
    print("\nTesting multiple skill expansion...")

    message = "Use $python-best-practices and $testing guidelines"
    expanded, skills_used = expand_skill_references(message)

    print(f"✓ Skills used: {skills_used}")
    print(f"  Original: {len(message)} chars")
    print(f"  Expanded: {len(expanded)} chars")

    return len(skills_used) >= 1  # At least python-best-practices should work


def test_nonexistent_skill():
    """Test handling of nonexistent skill references."""
    print("\nTesting nonexistent skill handling...")

    message = "Use $nonexistent-skill please"
    expanded, skills_used = expand_skill_references(message)

    # Should keep original $nonexistent-skill in text
    if "$nonexistent-skill" in expanded:
        print("✓ Nonexistent skill reference preserved in output")
        print(f"  Skills used: {skills_used}")
        return True
    else:
        print("✗ Nonexistent skill reference was modified unexpectedly")
        return False


def main():
    """Run all tests."""
    print("=" * 60)
    print("Skills System Integration Tests")
    print("=" * 60)

    tests = [
        ("Skill Loading", test_skill_loading),
        ("Skill Retrieval", test_skill_retrieval),
        ("Skill Search", test_skill_search),
        ("Skill Expansion", test_skill_expansion),
        ("Multiple Skills", test_multiple_skills),
        ("Nonexistent Skill", test_nonexistent_skill),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"\n✗ {test_name} failed with exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((test_name, False))

    print("\n" + "=" * 60)
    print("Test Results Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {test_name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
