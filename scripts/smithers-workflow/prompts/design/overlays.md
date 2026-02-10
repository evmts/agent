# Overlays & Panels

## 7) Overlays & panels

### 7.1 Command palette (Cmd+P)

IDE-only overlay (callable globally, see shortcuts)

Scrim `black@35%`; Panel: width 420–680px (65% window max 680), height 320–460px (55% window max 460), radius 10, `surface2`, shadow overlay spec

Layout two-pane: left results list, right preview (first 20 lines, 8KB)

Modes: default file search, command mode prefix `>` search commands

Keys: Up/Down navigate, Enter open, Esc dismiss

Animation: appear scale 0.97 + opacity spring (0.25s bounce 0.15), dismiss 0.15s ease-in

### 7.2 Search panel (Cmd+Shift+F)

Top-anchored slide-down (IDE); Width 55% max 560px, height 65% max 520px, `surface2`, slide + opacity animation

**Input row (HStack):** text field fills placeholder "Search in files...", regex toggle (icon `.*` — active accent bg), case-sensitive toggle (icon `Aa` — active accent bg), close button trailing

**Results area (two-pane):**

Left results list (grouped by file): file header icon + filename + match count badge ("12 matches"), match rows indented line number tertiary + highlighted match text + context; Click match opens file at line highlights match; Keys arrows navigate Enter opens

Right preview pane: ~10 lines context around selected match, match highlighted `accent@20%`, syntax TreeSitter, file path + line number top

**Summary bar (bottom):** "N results in M files" 11pt secondary, search time "0.12s"

Backend ripgrep fast workspace search, respects `.gitignore`/`.jj/ignore`

### 7.3 Toast notifications

Bottom-center above status bar (IDE) or composer (Chat); Auto dismiss 2–3s, slide up + fade, `surface2` radius 10

### 7.4 Progress bar

Top edge window; Height default 3pt (1–8 configurable), track `white@6%`, fill accent, auto-hide 0.45s after complete

### 7.5 Keyboard shortcuts panel (Cmd+/)

Right-side slide-in; Width 260–320pt, `surface2`, search field top, sections grouped by category

### 7.6 Skills system

Skills = reusable AI instruction packages (plugins) extend agent capabilities. Each skill = `SKILL.md` YAML frontmatter + markdown body.

#### Skill discovery

Scanned priority order:

1. `<workspace>/.agents/skills/` — project-scoped (checked into repo)
2. `~/.agents/skills/` — user-scoped (personal cross-project)
3. `/etc/codex/skills/` — admin-scoped (organization-wide)
4. `$CODEX_HOME/skills/.system/` — system-scoped (bundled defaults)

Each `SKILL.md` YAML frontmatter:

```yaml
---
name: react-component
description: Generate React components following project conventions
author: team
version: 1.0.0
tags: [react, frontend, components]
allowedTools: [read_file, write_file, run_terminal]
argumentHints: [component name, props interface]
---
```

Markdown body = AI instruction set, injected agent context when skill activated

#### Skill activation

Per-chat-session (not global); Active skills injected AI context system instructions; Invocation explicit (`$skill-name` composer) or implicit (AI recognizes relevant); Status bar shows active skills (6.4)

#### Skill modals

Available either window, presented sheets active window (radius 16 padding 16 `surface2`)

**Skill Browser (`SkillBrowserView`):** search field top (filters name/description/tags), grid/list available skills remote registry; Each card: name, description, author, tags, install button; Installed show "Installed" badge

**Skill List (`SkillListView`):** all installed grouped scope (Project/User/Admin/System); Each row: name, scope badge, description preview; Trailing toggle switch active/inactive current session; Context: Reveal Finder, Edit, Uninstall

**Skill Detail (`SkillDetailView`):** full metadata (name, description, author, version, tags, allowed tools), instructions preview markdown scrollable; Actions: Activate, Edit, Uninstall

**Create Skill Wizard (`CreateSkillWizardView`):** multi-step: 1) Name & description text fields, 2) Scope (Project/User), 3) Allowed tools checkbox list, 4) Instructions markdown editor, 5) Review & create preview + save; Optional `CodebaseAnalyzer` suggests templates based detected language/framework

**Skill Use popover (composer):** triggered Sparkles button composer footer; Shows installed skills toggles activate/deactivate current session; Quick filter name; "Browse Skills" link opens full Browser
