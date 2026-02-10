# Design Spec: Overlays & Panels (Section 7)

## 7) Overlays & panels

### 7.1 Command palette (Cmd+P)

**IDE-only overlay** (but callable globally; see shortcuts section).

- Scrim: black @ 35% (dark)
- Panel:

  - Width: 420–680px (65% of window), max 680
  - Height: 320–460px (55% of window), max 460
  - Radius: 10
  - Background: `surface2`
  - Shadow: overlay shadow spec

- Layout: two-pane

  - Left: results list
  - Right: preview (first 20 lines, 8KB)

- Modes:

  - Default: file search
  - Command mode: prefix `>` to search commands

- Keyboard:

  - Up/Down to navigate
  - Enter to open
  - Esc to dismiss

- Animation:

  - Appear: scale 0.97 + opacity, spring (0.25s, bounce 0.15)
  - Dismiss: 0.15s ease-in

### 7.2 Search panel (Cmd+Shift+F)

Top-anchored slide-down panel (IDE).

- Width: 55%, max 560px
- Height: 65%, max 520px
- Background: `surface2`
- Slide + opacity animation

**Search input row (HStack):**

- Text field (fills) with placeholder "Search in files..."
- **Regex toggle** (icon button: `.*`): Enables regular expression matching. Active state: accent background.
- **Case-sensitive toggle** (icon button: `Aa`): Toggles case sensitivity. Active state: accent background.
- Close button (trailing)

**Results area (two-pane):**

- **Left: results list** (grouped by file)

  - File header row: file icon + filename + match count badge (e.g., "12 matches")
  - Match rows (indented): line number (tertiary) + highlighted matching text with context
  - Click on match: opens file in editor at that line, highlights the match
  - Keyboard: Arrow Up/Down to navigate matches, Enter to open

- **Right: preview pane** (context around selected match)

  - Shows ~10 lines of code surrounding the selected match
  - Match highlighted with `accent@20%` background
  - Syntax highlighting applied (TreeSitter)
  - File path + line number shown at top of preview

**Summary bar (bottom):**

- "N results in M files" (11pt secondary)
- Search time indicator (e.g., "0.12s")

**Backend:** Uses ripgrep for fast workspace-wide search. Respects `.gitignore` / `.jj/ignore`.

### 7.3 Toast notifications

Bottom-center, above status bar (IDE) or above composer (Chat).

- Auto dismiss 2–3s
- Slide up + fade
- Background: `surface2`, radius 10

### 7.4 Progress bar

Top edge of window

- Height: default 3pt (1–8 configurable)
- Track: `white@6%`
- Fill: accent
- Auto-hide after 0.45s when complete

### 7.5 Keyboard shortcuts panel (Cmd+/)

Right-side slide-in

- Width: 260–320pt
- Background: `surface2`
- Search field at top
- Sections grouped by category

### 7.6 Skills system

Skills are reusable AI instruction packages (like plugins) that extend what the AI agent can do. Each skill is a `SKILL.md` file with YAML frontmatter + markdown body.

#### Skill discovery

Skills are scanned from multiple directories in priority order:

1. **`<workspace>/.agents/skills/`** — Project-scoped skills (checked into repo).
2. **`~/.agents/skills/`** — User-scoped skills (personal, cross-project).
3. **`/etc/codex/skills/`** — Admin-scoped skills (organization-wide).
4. **`$CODEX_HOME/skills/.system/`** — System-scoped skills (bundled defaults).

Each skill directory contains a `SKILL.md` with YAML frontmatter:

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

The markdown body below the frontmatter is the AI instruction set — injected into the agent's context when the skill is activated.

#### Skill activation

- Skills are activated **per-chat-session** (not globally).
- Active skills are injected into the AI context as system instructions.
- Invocation: explicit (`$skill-name` in composer) or implicit (AI recognizes when a skill is relevant).
- Status bar indicator shows active skills (see section 6.4).

#### Skill modals

Available from either window. Presented as sheets on the **active window** (radius 16, padding 16, background `surface2`).

**Skill Browser (`SkillBrowserView`):**

- Search field at top (filters by name, description, tags)
- Grid or list of available skills from remote registry
- Each card: name, description, author, tags, install button
- Installed skills show "Installed" badge instead of install button

**Skill List (`SkillListView`):**

- All installed skills grouped by scope (Project / User / Admin / System)
- Each row: skill name, scope badge, description preview
- Trailing: toggle switch (active/inactive for current session)
- Context menu: Reveal in Finder, Edit, Uninstall

**Skill Detail (`SkillDetailView`):**

- Full metadata: name, description, author, version, tags, allowed tools
- Skill instructions preview (markdown body, scrollable)
- Action buttons: Activate, Edit, Uninstall

**Create Skill Wizard (`CreateSkillWizardView`):**

- Multi-step wizard:

  1. **Name & description** — text fields
  2. **Scope selection** — Project / User (determines save location)
  3. **Allowed tools** — checkbox list of available tools
  4. **Instructions** — markdown editor for the skill body
  5. **Review & create** — preview + save

- Optional: **CodebaseAnalyzer** suggests skill templates based on detected project language/framework.

**Skill Use popover (from composer):**

- Triggered by the Sparkles button in the composer footer.
- Shows installed skills with toggles to activate/deactivate for the current session.
- Quick filter by name.
- "Browse Skills" link opens the full Skill Browser.
