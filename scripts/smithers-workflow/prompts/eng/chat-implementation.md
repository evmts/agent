# Chat Implementation

## Root Structure

```swift
struct ChatWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sidebarMode: SidebarMode = .chats

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(mode: $sidebarMode)
        } detail: {
            ChatDetailView()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
    }
}
```

## Sidebar

**Mode bar:** 3 buttons in HStack. `ModeBarItemButton` — icon + label, selected = accent pill. Animation: `.spring(duration: 0.2)`.

**Session list:** `List(selection:)` bound to `chat.selectedSession`. Sections from timestamps. `ChatSessionRow`: title (12pt semibold), trailing timestamp (10pt tertiary), 2-line preview (10pt tertiary). Context menu: Rename (inline), Delete (confirmation).

**JJ panel:** `DisclosureGroup` sections. Working copy rows with M/A/D badges. Change log rows + context menus (View Diff, Describe, Squash, Abandon). Bookmarks, Op log, Snapshots.

**Agent dashboard:**

Key monitoring surface. Active visible; past toggleable.

- **"ACTIVE AGENTS" header** — 10px uppercase tracking, tertiary
- **Agent rows:**
  - Status dot (8px) — blue working (glow), green completed, red failed, gray idle
  - Agent name — 11px semibold primary (e.g., "CodeReview", "TestWriter")
  - Task desc — 10px tertiary, truncated
  - Change count badge — pill if changes > 0
- **Sort** — Active/working top
- **Past toggle** — Show/hide completed/failed
- **Click to unhide** — Opens `.chat` tab in workspace panel
- **Hover** — `sidebar-hover` bg
- **"New Agent" button** — Accent, spawns sub-agent via orchestrator

## Detail Area

**Title bar (28pt):** Centered workspace name, trailing "Open Editor" `IconButton` → `appModel.windowCoordinator.showWorkspacePanel()`.

**Messages zone:** `ScrollViewReader` + `ScrollView` + `LazyVStack(spacing: 10)`. Each msg `.id(message.id)`. Auto-scroll when near bottom (`.easeOut(duration: 0.2)`). "Jump to latest" when scrolled up.

**Message bubbles:**

- `UserMessageBubble` — trailing align, `UnevenRoundedRectangle(topLeading: 12, bottomLeading: 12, bottomTrailing: 4, topTrailing: 12)`, `chat.bubble.user` bg, max width 80%
- `AssistantMessageBubble` — leading, `chat.bubble.assistant` bg. Markdown. File paths matching `path:line:col` → links calling `appModel.showInEditor()`
- `CommandBubble` — leading, 90% width, monospaced cmd + streaming output + exit badge
- `DiffPreviewCard` — leading, 90%, file list + summary + 8-line preview + status badge + "Open in Editor"
- `StatusMessageBubble` — centered, small muted pill

**Hover action bar:** After 150ms hover. Above bubble. Dark bg (`black@30%`), icon buttons: Fork, Copy, Retry, Edit, Revert, More.

**Streaming:** When `chat.isTurnInProgress`, last assistant msg live-updates via `chat.appendDelta()`. Mutate text in-place. Avoid re-parsing full markdown — append new run, re-parse affected tail only.

## Composer

`ChatComposerZone`:

- `ComposerContainer` — rounded rect (10pt), `chat.input.bg` bg, `white@6%` border
- Multiline `TextField(axis: .vertical)`, `.lineLimit(1...4)`, 10pt padding
- `AttachmentStrip` — 56pt thumbnails, horizontal scroll, X to remove
- Footer: Send (32x32, accent, up-arrow) when idle, Interrupt (32x32, danger, stop) when streaming
- Keyboard: Return sends, Shift+Return newline, Esc interrupts
- Drop target: `.dropDestination(for: Data.self)` with accent border highlight
- Paste images: `.onPasteCommand(of: [UTType.image])`

## Welcome Screen

Shown when `chat.messages.isEmpty`:

- Centered `VStack(spacing: 24)`, max width 640
- "How can I help you?" — 28pt semibold
- Project name — 16pt secondary (if workspace open)
- Category pills: HStack of `PillButton`s (Create, Explore, Code, Learn) with SF symbols
- **AI-generated suggested prompts:** 4 cards from `SuggestionService`, NOT hardcoded
  - First launch (no workspace): polished defaults
  - Subsequent: `SuggestionService` analyzes workspace, updates in-place
  - Impl: calls `codex-app-server` with suggestion prompt, cached per-workspace, refreshed on workspace change or 5min idle
  - Cards: white@6% bg, 8pt radius, 12pt padding, text + trailing arrow
- Clicking pill fills composer with prefix. Clicking suggestion fills + sends.
