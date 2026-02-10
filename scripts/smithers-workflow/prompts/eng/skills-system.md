# Skills System

## 12. Skills System

### 12.1 Discovery

`SkillScanner` searches in priority order:
1. `<workspace>/.agents/skills/` (project)
2. `~/.agents/skills/` (user)
3. `/etc/codex/skills/` (admin)
4. `$CODEX_HOME/skills/.system/` (system)

Each skill = directory with `SKILL.md` (YAML frontmatter: name, description, author, version, tags, allowedTools + markdown body = instructions passed to AI).

### 12.2 Activation

Per-chat session. Active skill instructions injected into AI context when sending messages. Status bar shows active skills, popover toggles.

### 12.3 UI

All skill views = sheets from active window:
- **SkillBrowserView** — browse registry, search, install
- **SkillListView** — manage installed (enable/disable/uninstall)
- **SkillUseView** — activate/deactivate for current chat
- **SkillDetailView** — full metadata
- **CreateSkillWizardView** — multi-step authoring wizard
