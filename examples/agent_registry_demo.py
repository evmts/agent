#!/usr/bin/env python3
"""
Demo script showing the multiple agents registry system.

This demonstrates how to:
1. List available agents
2. Get agent configurations
3. Create agents with different capabilities
4. Understand agent permissions
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from agent import (
    create_agent,
    get_agent_config,
    list_agent_names,
    list_agents,
    AgentMode,
)


def main():
    print("=" * 80)
    print("AGENT REGISTRY SYSTEM DEMO")
    print("=" * 80)

    # List all available agents
    print("\n1. Available Agents:")
    print("-" * 80)
    for name in list_agent_names():
        config = get_agent_config(name)
        if config:
            print(f"\n  {name.upper()}")
            print(f"    Mode: {config.mode.value}")
            print(f"    Description: {config.description}")

    # Show detailed configuration for each built-in agent
    print("\n\n2. Detailed Agent Configurations:")
    print("-" * 80)

    for agent_config in list_agents():
        if agent_config.name in ["build", "general", "plan", "explore"]:
            print(f"\n  {agent_config.name.upper()} AGENT")
            print(f"    Description: {agent_config.description}")
            print(f"    Mode: {agent_config.mode.value}")
            print(f"    Temperature: {agent_config.temperature}")

            # Show enabled tools
            enabled_tools = [k for k, v in agent_config.tools_enabled.items() if v]
            disabled_tools = [k for k, v in agent_config.tools_enabled.items() if not v]

            print(f"    Enabled tools: {', '.join(enabled_tools)}")
            if disabled_tools:
                print(f"    Disabled tools: {', '.join(disabled_tools)}")

            # Show shell restrictions
            if agent_config.allowed_shell_patterns:
                print(f"    Shell restrictions: {len(agent_config.allowed_shell_patterns)} allowed patterns")
            else:
                print(f"    Shell restrictions: None (all commands allowed)")

    # Demonstrate shell command validation for restricted agents
    print("\n\n3. Shell Command Validation Examples:")
    print("-" * 80)

    plan_config = get_agent_config("plan")
    if plan_config:
        print("\n  PLAN agent (read-only with restricted shell):")
        test_commands = [
            ("ls -la", "List directory"),
            ("git status", "Check git status"),
            ("grep 'pattern' file.txt", "Search file contents"),
            ("rm -rf /", "Delete files"),
            ("python script.py", "Execute Python"),
            ("npm install", "Install packages"),
        ]

        for cmd, desc in test_commands:
            allowed = plan_config.is_shell_command_allowed(cmd)
            status = "✓ ALLOWED" if allowed else "✗ BLOCKED"
            print(f"    {status}: {cmd:30s} ({desc})")

    explore_config = get_agent_config("explore")
    if explore_config:
        print("\n  EXPLORE agent (fast codebase exploration):")
        test_commands = [
            ("git log --oneline", "View git history"),
            ("find . -name '*.py'", "Find Python files"),
            ("rg 'pattern'", "Ripgrep search"),
            ("npm install", "Install packages"),
        ]

        for cmd, desc in test_commands:
            allowed = explore_config.is_shell_command_allowed(cmd)
            status = "✓ ALLOWED" if allowed else "✗ BLOCKED"
            print(f"    {status}: {cmd:30s} ({desc})")

    # Show how to create agents
    print("\n\n4. Creating Agents:")
    print("-" * 80)

    print("\n  Creating BUILD agent (default):")
    build_agent = create_agent(agent_name="build")
    print("    ✓ Build agent created with full tool access")

    print("\n  Creating PLAN agent (read-only):")
    plan_agent = create_agent(agent_name="plan")
    print("    ✓ Plan agent created with read-only access")

    print("\n  Creating EXPLORE agent (fast search):")
    explore_agent = create_agent(agent_name="explore")
    print("    ✓ Explore agent created for codebase navigation")

    print("\n\n5. Agent Use Cases:")
    print("-" * 80)

    use_cases = {
        "build": [
            "Full development workflow",
            "Implementing new features",
            "Running tests and builds",
            "General coding assistance",
        ],
        "general": [
            "Parallel task execution",
            "Multi-step operations",
            "Concurrent file processing",
            "Subagent coordination",
        ],
        "plan": [
            "Code review and analysis",
            "Architecture planning",
            "Read-only exploration",
            "Strategy development",
        ],
        "explore": [
            "Fast codebase navigation",
            "Pattern discovery",
            "Quick code searches",
            "Understanding project structure",
        ],
    }

    for agent_name, cases in use_cases.items():
        print(f"\n  {agent_name.upper()}:")
        for case in cases:
            print(f"    • {case}")

    print("\n" + "=" * 80)
    print("Demo completed successfully!")
    print("=" * 80 + "\n")


if __name__ == "__main__":
    main()
