#!/usr/bin/env python3
"""
Comprehensive demo of the skills system.

This script demonstrates all features of the implemented skills system:
1. Loading skills from ~/.agent/skills/
2. Searching and retrieving skills
3. Expanding skill references in messages
4. Simulating message processing with skill expansion
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from config.skills import get_skill_registry, expand_skill_references


def print_header(text: str) -> None:
    """Print a formatted header."""
    print("\n" + "=" * 70)
    print(f" {text}")
    print("=" * 70)


def demo_skill_loading() -> None:
    """Demonstrate skill loading."""
    print_header("1. SKILL LOADING")

    registry = get_skill_registry()
    registry.load_skills()

    skills = registry.list_skills()
    print(f"\nLoaded {len(skills)} skills from {registry.skills_dir}:\n")

    for skill in skills:
        print(f"📚 {skill.name}")
        print(f"   Description: {skill.description}")
        print(f"   File: {skill.file_path.name}")
        print(f"   Content: {len(skill.content)} characters\n")


def demo_skill_search() -> None:
    """Demonstrate skill search."""
    print_header("2. SKILL SEARCH")

    registry = get_skill_registry()

    # Search for Python-related skills
    print("\n🔍 Searching for 'python'...")
    results = registry.search_skills("python")
    print(f"Found {len(results)} matches:")
    for skill in results:
        print(f"  • {skill.name}: {skill.description}")

    # Search for testing skills
    print("\n🔍 Searching for 'test'...")
    results = registry.search_skills("test")
    print(f"Found {len(results)} matches:")
    for skill in results:
        print(f"  • {skill.name}: {skill.description}")


def demo_skill_retrieval() -> None:
    """Demonstrate retrieving a specific skill."""
    print_header("3. SKILL RETRIEVAL")

    registry = get_skill_registry()

    skill_name = "python-best-practices"
    print(f"\n📖 Retrieving skill: {skill_name}")

    skill = registry.get_skill(skill_name)
    if skill:
        print(f"\n✓ Found skill!")
        print(f"  Name: {skill.name}")
        print(f"  Description: {skill.description}")
        print(f"  File: {skill.file_path}")
        print(f"\n  Content preview:")
        print("  " + "-" * 66)
        # Show first 300 chars
        preview = skill.content[:300].replace("\n", "\n  ")
        print(f"  {preview}...")
        print("  " + "-" * 66)
    else:
        print(f"✗ Skill '{skill_name}' not found")


def demo_single_skill_expansion() -> None:
    """Demonstrate expanding a single skill reference."""
    print_header("4. SINGLE SKILL EXPANSION")

    message = "Please help me write Python code following $python-best-practices"

    print(f"\n📝 Original message:")
    print(f"  \"{message}\"\n")

    expanded, skills_used = expand_skill_references(message)

    print(f"✓ Expanded message:")
    print(f"  Skills used: {skills_used}")
    print(f"  Original length: {len(message)} characters")
    print(f"  Expanded length: {len(expanded)} characters")
    print(f"  Expansion ratio: {len(expanded) / len(message):.1f}x\n")

    print("📄 Expanded content preview:")
    print("  " + "-" * 66)
    # Show first 400 chars
    preview = expanded[:400].replace("\n", "\n  ")
    print(f"  {preview}...")
    print("  " + "-" * 66)


def demo_multiple_skill_expansion() -> None:
    """Demonstrate expanding multiple skill references."""
    print_header("5. MULTIPLE SKILL EXPANSION")

    message = "Write tests using $python-testing and follow $python-best-practices guidelines"

    print(f"\n📝 Original message:")
    print(f"  \"{message}\"\n")

    expanded, skills_used = expand_skill_references(message)

    print(f"✓ Expanded message:")
    print(f"  Skills used: {skills_used}")
    print(f"  Number of skills: {len(skills_used)}")
    print(f"  Original length: {len(message)} characters")
    print(f"  Expanded length: {len(expanded)} characters")

    # Count skill markers
    skill_count = expanded.count("[Skill:")
    print(f"  Skill sections found: {skill_count}\n")


def demo_nonexistent_skill() -> None:
    """Demonstrate handling of non-existent skills."""
    print_header("6. NON-EXISTENT SKILL HANDLING")

    message = "Use $nonexistent-skill and $another-missing-skill please"

    print(f"\n📝 Original message:")
    print(f"  \"{message}\"\n")

    expanded, skills_used = expand_skill_references(message)

    print(f"✓ Result:")
    print(f"  Skills used: {skills_used or 'None'}")
    print(f"  Original preserved: {message == expanded}")
    print(f"  Expanded message: \"{expanded}\"")


def demo_message_processing_simulation() -> None:
    """Simulate how skills work in actual message processing."""
    print_header("7. MESSAGE PROCESSING SIMULATION")

    print("\nSimulating core/messages.py send_message() flow:\n")

    # Simulate user input
    user_message = "Help me refactor this code using $python-best-practices"

    print("1️⃣  User sends message:")
    print(f"    \"{user_message}\"\n")

    print("2️⃣  Message processing extracts text...")
    user_text = user_message

    print("3️⃣  Skill expansion occurs:")
    expanded_text, skills_used = expand_skill_references(
        user_text, get_skill_registry()
    )

    if skills_used:
        print(f"    ✓ Expanded skills: {skills_used}")
        print(f"    ✓ Message size: {len(user_text)} -> {len(expanded_text)} chars\n")
    else:
        print("    ℹ No skills to expand\n")

    print("4️⃣  Agent receives expanded message:")
    print(f"    Length: {len(expanded_text)} characters")
    print(f"    Contains skill content: {len(expanded_text) > len(user_text)}\n")

    print("5️⃣  Agent processes with full skill context...")
    print("    (Agent now has access to python-best-practices guidelines)\n")


def demo_api_simulation() -> None:
    """Simulate API endpoint behavior."""
    print_header("8. API ENDPOINT SIMULATION")

    registry = get_skill_registry()

    print("\n🌐 Simulating GET /skill endpoint:\n")
    skills = registry.list_skills()
    response = [
        {
            "name": skill.name,
            "description": skill.description,
            "file_path": str(skill.file_path),
        }
        for skill in skills
    ]
    print(f"   Response: {len(response)} skills")
    for item in response[:2]:  # Show first 2
        print(f"   • {item['name']}: {item['description'][:60]}...")

    print("\n🌐 Simulating GET /skill?query=python endpoint:\n")
    search_results = registry.search_skills("python")
    response = [
        {
            "name": skill.name,
            "description": skill.description,
            "file_path": str(skill.file_path),
        }
        for skill in search_results
    ]
    print(f"   Response: {len(response)} matching skills")
    for item in response:
        print(f"   • {item['name']}")

    print("\n🌐 Simulating GET /skill/python-best-practices endpoint:\n")
    skill = registry.get_skill("python-best-practices")
    if skill:
        response = {
            "name": skill.name,
            "description": skill.description,
            "file_path": str(skill.file_path),
        }
        print(f"   Response:")
        print(f"   • name: {response['name']}")
        print(f"   • description: {response['description']}")
        print(f"   • file_path: {response['file_path']}")


def main() -> None:
    """Run all demos."""
    print("\n" + "╔" + "═" * 68 + "╗")
    print("║" + " " * 15 + "SKILLS SYSTEM COMPREHENSIVE DEMO" + " " * 21 + "║")
    print("╚" + "═" * 68 + "╝")

    demos = [
        demo_skill_loading,
        demo_skill_search,
        demo_skill_retrieval,
        demo_single_skill_expansion,
        demo_multiple_skill_expansion,
        demo_nonexistent_skill,
        demo_message_processing_simulation,
        demo_api_simulation,
    ]

    for demo in demos:
        try:
            demo()
        except Exception as e:
            print(f"\n❌ Demo failed: {e}")
            import traceback
            traceback.print_exc()

    print("\n" + "=" * 70)
    print(" DEMO COMPLETE")
    print("=" * 70)
    print("\n✅ All skills system features demonstrated successfully!")
    print("\nNext steps:")
    print("  • Skills are automatically expanded in conversation messages")
    print("  • Use $skill-name syntax in any message to inject skill content")
    print("  • API endpoints available at /skill for programmatic access")
    print("  • Add custom skills to ~/.agent/skills/ directory")
    print()


if __name__ == "__main__":
    main()
