# Chat Window Spec

## 5.1 Layout

Root: `NavigationSplitView` — sidebar 200–360pt (default 260pt), detail flexible

`ChatWindowRootView` → `ChatSidebarView` + `ChatDetailView`

## 5.2 Sidebar hierarchy

`ChatSidebarView` (VStack) → `SidebarModeBar` (40pt) + Divider + `ChatSidebarContent`

Modes: Chats (NewChatButton + SearchField + SessionList), Source (JJPanelSidebar), Agents (AgentDashboardSidebar)

### 5.2.1 Mode bar

40pt height, 8pt padding, `chat.sidebar.bg`

3 `ModeBarItemButton`: Chats (`bubble.left.and.bubble.right`), Source (`arrow.triangle.branch`), Agents (`person.3`)

Selected: accent text, `accent@12%` pill (radius 8); Inactive: secondary text, no bg; Hover: `white@4%`

### 5.2.2 Chats mode — Session list

Groups: Today / Yesterday / This Week / Older — headers uppercase `type.xs` tertiary, padding 8pt top / 6pt bottom / 12pt h

`ChatSessionRow`: 56pt, padding 10pt v / 12pt h; Title 12pt semibold primary, timestamp 10pt tertiary trailing, preview 10pt tertiary max 2 lines; Hover `chat.sidebar.hover`, selected `chat.sidebar.selected`; Context menu: Rename / Delete / Duplicate; Inline rename: Enter commits, Esc cancels

### 5.2.3 Source mode — JJ panel

Compact JJ (Jujutsu) workflow: viewing changes, committing, branching, git remotes

`JJPanelSidebar` sections: WorkingCopy, ChangeLog, Bookmarks, OpLog, Snapshots

Section header (32pt): disclosure triangle, title 11pt medium, optional trailing action; Content rows 36–44pt

**Working Copy:**

Action buttons: Describe (pencil — inline text field, `CommitStyleDetector` matches team style from last 30 commits), New (plus — `jj new`), Snapshot (camera — Describe + New)

File rows: status badge M/A/D/? (M=warning, A=success, D=danger, ?=tertiary), filename 11pt + path tertiary if not unique, `+N −M` monospace 10pt success/danger; Click opens diff (chat card or IDE tab per pref); Context: Reveal / Open / Copy Path / Revert

**Change Log:**

Rows: change ID (short hash mono), description 11pt, author, relative time; Working copy highlighted accent; Context: Squash / Abandon (confirm) / Edit / Describe / Create bookmark / Copy ID

**Bookmarks:**

Rows: name 11pt medium, tracking (local/remote), change ID; Context: Git Push (`jj git push -b <name>`) / Delete (confirm) / Rename / Copy Name

Footer buttons: Push All Tracked (`jj git push --tracked`), Fetch (`jj git fetch`)

**Operations Log:**

Rows: operation description, relative timestamp; Context: Restore (`jj op restore <id>`, confirm dialog), Undo (`jj undo`, recent only)

**Snapshots:**

Rows: description, time, trigger (auto/manual/agent); Click: revert preview dialog + diff (confirm/cancel); AI turns auto-create (2s debounce), manual saves optional (pref)

**Conflict indicator:** warning banner top of Source panel — `warning@12%` bg, triangle icon, "N conflicts in M files", click opens conflict list

### 5.2.4 Agents mode — Dashboard

`AgentDashboardSidebar`: New Agent button (PrimaryButton full width) + ActiveAgentsList + PastAgentsList (collapsible) + MergeQueueList

**Agent row:** status dot 8pt — Idle (tertiary), Working (`color.info` pulse 0.8s), Completed (`color.success`), Failed (`color.danger`), Cancelled (tertiary strikethrough), Conflicted (`color.warning`), In Queue (tertiary + badge), Merged (`color.success` + checkmark); Title 11pt medium, subtitle 10pt tertiary 1 line truncated, files badge monospace `white@8%` radius 4; Hover actions 24×24: Open Chat (bubble — unhides `.chat` tab in IDE), Open Diff (diff icon), Merge (merge icon, confirm + preview), Cancel (stop, confirm "Changes preserved in JJ branch"); Click row expands: task, start time, duration, file list

**Config:** Concurrent limit (default 4, configurable, excess queued); Setup commands (optional shell per-workspace)

**Lifecycle:** Each agent: JJ workspace branch (`jj workspace add`), Codex session (multiplexed), polls file changes, reports events; Complete: ready to merge or show conflicts

**Merge queue (post-MVP, UI reserved):** entries show agent, priority (low/normal/high/urgent), status (waiting/testing/merging/merged/failed); drag reorder, test status spinner/badge, auto-merge toggle; MVP: simple Merge button

---

## 5.3 Detail view

`ChatDetailView` (VStack spacing 0): TitleBarZone (28pt) + Divider + MessagesZone (fills) + Divider + ComposerZone

### 5.3.1 Title bar

28pt, `titlebar.bg`; HStack: leading spacer, center workspace name 11pt `titlebar.fg`, trailing OpenEditorButton (icon `rectangle.split.2x1`, tooltip "Open Editor"); Click: create & show IDE or bring to front

### 5.3.2 Messages zone

`ScrollViewReader` + `ScrollView` + `LazyVStack` (spacing 10–12), padding 16pt h / 16pt top / 12pt bottom

Auto-scroll: pin to bottom on new text if at bottom, else show "Jump to latest" button (bottom-right above composer, 36pt, radius 8)

#### Message types

1. **User bubble:** trailing, max 80% width, `UnevenRoundedRectangle` corners 12 tail 4 (bottom-right), `chat.bubble.user`, 13pt primary line-height 1.5, markdown (bold/italic/code)

2. **Assistant bubble:** leading, tail bottom-left, `chat.bubble.assistant`; Headings 15pt semibold, code blocks mono `white@4%` radius 8 padding 10pt, inline code mono `white@6%`; File paths `path:line:col` clickable (underline hover, opens IDE)

3. **Command bubble:** leading, max 90%, `chat.bubble.command`; Header `$ command` mono 13pt semibold + spinner/exit badge, CWD 10pt tertiary, output mono 12–13pt selectable h-scroll; Running: spinner "Running…" secondary, stream in place smooth height

4. **Diff card:** leading, max 90%, `chat.bubble.diff`; Title "N files changed" or filename 13pt medium, file list (5 max then "+N more"), summary `+N −M` mono success/danger, preview 8 lines mono diff coloring; Footer: status badge (Applying/Applied/Failed/Declined) + "Open in Editor" button; Click: full diff viewer (sheet or IDE tab per pref); "Open in Editor" always opens IDE + selects diff/file

5. **Status:** neutral pill centered/leading, `chat.bubble.status`, 11pt secondary

6. **Starter prompt:** new/empty chats only, renders welcome (5.5)

#### Message hover action bar

150ms delay, floats above bubble edge; `black@30%` bg, `white@6%` border, radius 8

Buttons: Fork (branch — new chat session inherits messages to this point, appears in sidebar + can open as `.chat` tab), Copy, Retry (assistant/last user), Edit & Resend (user), Revert (if JJ snapshot), More (ellipsis → "Rollback to here"); Dismiss on mouse leave

### 5.3.3 Thinking

Leading bubble, spinner + "Thinking…", assistant bubble style, 8pt padding

### 5.4 Chat composer (input zone)

- `ChatComposerZone` (VStack spacing 8, padding 12–16)

  - `ComposerContainer` (rounded, 10 radius)

    - `ComposerTextField` (multiline 1–4 lines)
    - optional `ComposerAttachmentStrip` (if images)

  - `ComposerFooterRow` (HStack)

    - Left: tiny hint text (optional, tertiary)
    - Right: Send / Interrupt button

**Composer container:**

- Background: `chat.input.bg`
- Border: 1px `white@6%`
- Padding:

  - 10pt internal padding around text

- Drop target:

  - On drag-over: border switches to accent, background accent@6%

**Composer action buttons (below text field, left-aligned row):**

- **Attach** (Paperclip icon) — opens file picker or triggers paste for images.
- **@Mention** (AtSign icon) — opens a popup to mention files, functions, or context items. Inserts `@filename` or `@symbol` references into the message that the AI can use for targeted context.
- **Skills** (Sparkles icon) — opens the skill activation popover. Shows installed skills with toggles to activate/deactivate for the current session. This is a primary entry point for skill discovery and management.

These buttons are always visible in the composer footer, left of the send button.

**Send button:**

- Size: 32×32
- Radius: 6
- Background: accent solid
- Icon: up arrow
- Hover: brighten +6%
- Disabled: if input empty AND no attachments

**Interrupt button:**

- Same size, background danger@25%, icon stop
- Only visible while AI turn is processing.

**Slash command popup:**

- Typing `/` at the start of the composer opens a slash command autocomplete popup.
- Commands: `/plan`, `/review`, `/diff`, `/fork`, `/new`, `/resume`, `/status`, `/compact`, `/mention`, `/init`, `/model`.
- Popup: surface2 background, radius 8, shadow, max 8 visible rows, arrow key navigation, Enter to select, Esc to dismiss.
- Commands can accept inline arguments (e.g., `/plan refactor the auth module`).

**@Mention popup:**

- Typing `@` opens a file/symbol autocomplete popup.
- Shows files from the workspace, filtered by typed text after `@`.
- Select to insert a file reference. Referenced files are included as context for the AI.
- Popup styled same as slash command popup.

**Steer mode (while agent is running):**

- While AI is streaming/working, the composer remains active.
- **Enter** sends a message that steers the agent in real-time (mid-turn correction).
- **Tab** queues a follow-up prompt for the next turn.
- A subtle indicator shows "Steer" vs "Queue" mode.

**Keyboard behavior:**

- Return: Send (or Steer if agent is running)
- Tab: Queue follow-up (if agent is running)
- Shift+Return: newline
- Cmd+Return: Send (redundant, but common)
- Esc: if AI streaming, interrupts; else clears focus

### 5.4.1 Image attachments

- Accept paste (Cmd+V), drag drop.
- `AttachmentStrip`:

  - Height: 56–72pt
  - Thumbnails: 56×56, radius 8
  - Horizontal scroll if >4
  - Each thumbnail has hover "x" to remove.

### 5.4.2 Fullscreen image viewer

- Presented as overlay above chat window (not sheet)
- Dark scrim: black@60%
- Centered image with max size 90% of window
- Close controls:

  - Esc closes
  - top-right X button

---

## 5.5 Chat empty / welcome screen

Shown for:

- new chat
- no messages yet in selected session

Layout: centered VStack with fixed max width 640.

1. Heading: 28pt semibold "How can I help you?"
2. Subheading: 16pt secondary project name (only if workspace open)
3. Category pills row (Create / Explore / Code / Learn)
4. **AI-generated suggested prompts** (4 rows)

   - Card bg: white@6%, border white@6%, radius 8
   - Row padding: 12pt
   - Trailing arrow icon

**Suggested prompts are AI-generated and workspace-aware, NOT hardcoded.** The `SuggestionService` analyzes the workspace on open and generates contextual suggestions based on:

- Recent files and edits (what the user has been working on)
- JJ status (uncommitted changes, conflicts, recent commits)
- Project type (detected language/framework — e.g., "Write tests for your new React component")
- Recent and repeated prompts (suggest follow-ups to common workflows)

Suggestions are cached per-workspace with a **5-minute refresh interval**. On first launch or before suggestions are ready, show polished defaults (e.g., "Explore this codebase", "Review recent changes", "Help me fix a bug", "Write documentation").

Interaction:

- Clicking a pill filters suggestions by category.
- Clicking a suggestion inserts full text into composer and focuses input.
