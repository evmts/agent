# Skills System

<metadata>
  <priority>medium</priority>
  <category>extensibility</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/, config/, tui/</affects>
</metadata>

## Objective

Implement a skills system that allows users to define reusable instruction sets that can be injected into conversations via `$skill-name` syntax or the `/skills` command.

<context>
Codex supports "skills" - markdown files with YAML frontmatter that define reusable prompts and instructions. Skills are useful for:
- Project-specific coding conventions
- Framework-specific best practices
- Company coding standards
- Task templates (PR review, refactoring, etc.)

Skills are discovered from `~/.codex/skills/` and can be mentioned in prompts or browsed via UI.
</context>

## Requirements

<functional-requirements>
1. Skill file format:
   - Location: `~/.agent/skills/**/*.md`
   - YAML frontmatter with name, description
   - Markdown body with instructions
2. Skill discovery:
   - Scan skills directory at startup
   - Watch for changes (optional)
   - Cache discovered skills
3. Skill usage:
   - `$skill-name` syntax in prompts
   - `/skills` command to browse and insert
4. Skill injection:
   - Insert skill content into system prompt
   - Support multiple skills per message
5. `/skills` UI:
   - List available skills
   - Show descriptions
   - Search/filter
   - Select to insert
</functional-requirements>

<technical-requirements>
1. Create skills directory structure
2. Implement skill file parser (YAML frontmatter + markdown)
3. Build skill registry for discovery
4. Add `/skills` handler to TUI
5. Implement `$skill` syntax parser
6. Inject skills into agent context
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `config/skills.py` (CREATE) - Skill loading and registry
- `agent/agent.py` - Skill injection into prompts
- `tui/main.go` - Add /skills command handler
- `tui/internal/components/skills/` (CREATE) - Skills browser UI
</files-to-modify>

<skill-file-format>
```markdown
---
name: python-best-practices
description: Best practices for Python code following PEP 8 and modern patterns
---

# Python Best Practices

When writing Python code, follow these guidelines:

## Style
- Use 4 spaces for indentation
- Maximum line length of 88 characters (black formatter)
- Use type hints for all function signatures

## Imports
- Group imports: stdlib, third-party, local
- Use absolute imports
- Avoid `from module import *`

## Code Quality
- Write docstrings for all public functions
- Use dataclasses for data containers
- Prefer f-strings over .format()
- Use context managers for resource management

## Error Handling
- Be specific with exception types
- Always log exceptions with context
- Use custom exceptions for domain errors
```
</skill-file-format>

<skill-registry>
```python
# config/skills.py

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import yaml
import re

@dataclass
class Skill:
    name: str
    description: str
    content: str
    file_path: Path

class SkillRegistry:
    def __init__(self, skills_dir: Path = None):
        self.skills_dir = skills_dir or Path.home() / ".agent" / "skills"
        self._skills: dict[str, Skill] = {}
        self._loaded = False

    def load_skills(self) -> None:
        """Discover and load all skill files."""
        self._skills.clear()

        if not self.skills_dir.exists():
            self.skills_dir.mkdir(parents=True, exist_ok=True)
            return

        for skill_file in self.skills_dir.rglob("*.md"):
            try:
                skill = self._parse_skill_file(skill_file)
                if skill:
                    self._skills[skill.name] = skill
            except Exception as e:
                logger.warning(f"Failed to parse skill {skill_file}: {e}")

        self._loaded = True

    def _parse_skill_file(self, path: Path) -> Optional[Skill]:
        """Parse a skill file with YAML frontmatter."""
        content = path.read_text()

        # Extract YAML frontmatter
        match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
        if not match:
            return None

        frontmatter = yaml.safe_load(match.group(1))
        body = match.group(2).strip()

        name = frontmatter.get("name")
        description = frontmatter.get("description", "")

        if not name or len(name) > 100:
            return None
        if len(description) > 500:
            description = description[:500]

        return Skill(
            name=name,
            description=description,
            content=body,
            file_path=path,
        )

    def get_skill(self, name: str) -> Optional[Skill]:
        """Get a skill by name."""
        if not self._loaded:
            self.load_skills()
        return self._skills.get(name)

    def list_skills(self) -> list[Skill]:
        """Get all available skills."""
        if not self._loaded:
            self.load_skills()
        return list(self._skills.values())

    def search_skills(self, query: str) -> list[Skill]:
        """Search skills by name or description."""
        query = query.lower()
        return [
            s for s in self.list_skills()
            if query in s.name.lower() or query in s.description.lower()
        ]

# Global instance
skill_registry = SkillRegistry()
```
</skill-registry>

<skill-injection>
```python
# agent/agent.py

def expand_skill_references(message: str, registry: SkillRegistry) -> tuple[str, list[str]]:
    """
    Expand $skill-name references in a message.

    Returns:
        Tuple of (expanded_message, list_of_skill_names_used)
    """
    skills_used = []
    skill_pattern = re.compile(r'\$([a-zA-Z0-9_-]+)')

    def replace_skill(match):
        skill_name = match.group(1)
        skill = registry.get_skill(skill_name)
        if skill:
            skills_used.append(skill_name)
            return f"\n\n[Skill: {skill.name}]\n{skill.content}\n[End Skill]\n\n"
        return match.group(0)  # Keep original if not found

    expanded = skill_pattern.sub(replace_skill, message)
    return expanded, skills_used


# In message processing
async def process_message(session_id: str, message: str):
    # Expand skill references
    expanded_message, skills_used = expand_skill_references(message, skill_registry)

    if skills_used:
        logger.info(f"Expanded skills: {skills_used}")

    # Continue with expanded message...
```
</skill-injection>

<skills-browser-ui>
```
┌──────────────────── Skills ────────────────────────┐
│ 🔍 Search: python                                  │
├────────────────────────────────────────────────────┤
│                                                    │
│ > python-best-practices                            │
│   Best practices for Python code following PEP 8  │
│                                                    │
│   python-testing                                   │
│   Guidelines for writing pytest tests             │
│                                                    │
│   python-async                                     │
│   Async/await patterns and best practices         │
│                                                    │
├────────────────────────────────────────────────────┤
│ [Enter: Insert] [↑↓: Navigate] [Esc: Close]       │
└────────────────────────────────────────────────────┘
```
</skills-browser-ui>

<slash-command>
```go
// In TUI slash command handler
case "/skills":
    skills, err := client.ListSkills()
    if err != nil {
        return fmt.Errorf("failed to list skills: %w", err)
    }

    if len(skills) == 0 {
        fmt.Println("No skills found. Add .md files to ~/.agent/skills/")
        return nil
    }

    // Show skills browser
    selected, err := showSkillsBrowser(skills)
    if err != nil || selected == nil {
        return nil // Cancelled
    }

    // Insert skill reference into composer
    m.composer.Insert(fmt.Sprintf("$%s ", selected.Name))
    return nil
```
</slash-command>

## Acceptance Criteria

<criteria>
- [x] Skills loaded from ~/.agent/skills/**/*.md
- [x] YAML frontmatter parsed (name, description)
- [x] `$skill-name` syntax expands in prompts
- [ ] `/skills` opens skills browser (TUI pending)
- [x] Search/filter in skills browser (API: GET /skill?search=query)
- [ ] Enter inserts `$skill-name` into composer (TUI pending)
- [x] Multiple skills can be used in one message
- [x] Missing skills reported gracefully
- [x] Skill content injected into agent context
- [x] Skills reloaded on file changes (POST /skill/reload)
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Create sample skills and test loading
3. Test $skill-name expansion in prompts
4. Test /skills browser UI
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `39-skills-system.md` to `39-skills-system.complete.md`
</completion>

## Implementation Hindsight

<hindsight>
**Completed:** 2024-12-17

**Key Implementation Notes:**
1. config/skills.py already existed with complete SkillRegistry implementation
2. Skill expansion integrated into core/messages.py before agent processing
3. API endpoints: GET /skill (list/search), GET /skill/{name}, POST /skill/reload
4. Uses regex \$([a-zA-Z0-9_-]+) to find skill references
5. LRU cache for performance on skill expansion
6. TUI /skills browser NOT implemented - backend API ready

**Files Modified:**
- `config/skills.py` - Skill loading and registry (pre-existed)
- `server/routes/skills.py` - Created API endpoints
- `server/routes/__init__.py` - Registered skills router
- `core/messages.py` - Integrated expand_skill_references before agent

**Prompt Improvements for Future:**
1. Note that config/skills.py already existed
2. Separate Python backend from Go TUI tasks
3. Specify API response format (SkillInfo model)
4. Add example skills in ~/.agent/skills/ for testing
5. Note that missing skills are preserved unchanged (not errors)
6. Consider circular skill reference detection if skills can reference other skills
</hindsight>
