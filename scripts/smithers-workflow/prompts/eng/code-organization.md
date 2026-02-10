## 3. Code Organization

### 3.1 Philosophy

**Feature-based organization** (following Ghostty's pattern). Code is organized by feature, not by architectural layer. Everything related to chat lives in `Features/Chat/`, everything related to the editor lives in `Features/Editor/`, etc. This makes features findable: when you need to understand how chat works, you look in one place.

There is no complex module dependency graph. Everything lives in a single Xcode app target, organized by directories. Any file can reference any other file — that's intentional. The directory structure provides the findability that separate modules would provide, without the overhead.

**Guiding principle:** "We're not trying to avoid the god object. We're just trying to break things up into smaller, easier to find files." A single god object with code modularly split across files is the correct architecture.

### 3.2 Directory responsibilities

Everything below is within `macos/Sources/`. Files reference each other directly — no imports needed between directories.

#### App/

App entry point, window coordination, and app-wide state.

```
App/
├── SmithersApp.swift            — @main, scene definitions, menu commands
├── AppModel.swift               — Composition root: the single @Observable god object
├── WorkspaceModel.swift         — Per-workspace state container
├── WindowCoordinator.swift      — Creates, shows, hides, focuses workspace panel windows
├── CloseGuard.swift             — Unsaved changes prompts for tab/window/app close
├── TmuxKeyHandler.swift         — Ctrl+A prefix key system
└── UpdateController.swift       — Sparkle integration
```

#### Ghostty/

Core libsmithers Swift wrapper (like Ghostty's `Ghostty/` directory). Contains the C FFI bridge.

```
Ghostty/
├── SmithersCore.swift          — Thin Swift wrapper around libsmithers C API (Unmanaged/callback pattern)
├── MockSmithersCore.swift      — Mock for parallel UI development
└── Surface View/               — If needed for terminal surface management
```

#### Features/

Feature-based organization. Each feature directory contains views, models, and any feature-specific logic.

##### Features/Chat/

```
Features/Chat/
├── Models/
│   ├── ChatMessage.swift        — Message model (role, kind, images, timestamps, turn tracking)
│   ├── ChatSession.swift        — Session metadata (id, title, creation date, last message preview)
│   └── ChatModel.swift          — Chat sessions, messages, streaming state (~250 lines)
├── Views/
│   ├── ChatWindowRootView.swift — NavigationSplitView (sidebar + detail)
│   ├── Sidebar/
│   │   ├── ChatSidebarView.swift        — Container: mode bar + content switcher
│   │   ├── SidebarModeBar.swift         — Chats / Source / Agents toggle
│   │   ├── ChatSessionList.swift        — Grouped session list
│   │   ├── ChatSessionRow.swift         — Individual session row
│   │   └── ChatSidebarSearchField.swift — Filter sessions
│   ├── Detail/
│   │   ├── ChatDetailView.swift         — VStack: title bar + messages + composer
│   │   ├── ChatTitleBarZone.swift
│   │   ├── ChatMessagesZone.swift
│   │   ├── MessageBubbles/              — User, assistant, command, diff, status bubbles
│   │   ├── MessageHoverActionBar.swift
│   │   ├── ChatComposerZone.swift       — Input + slash commands + @mention + skills
│   │   ├── SlashCommandPopup.swift      — Slash command autocomplete
│   │   ├── MentionPopup.swift           — @mention file/symbol picker
│   │   └── ChatWelcomeScreen.swift      — Empty state with AI-generated suggestions
│   └── DiffSheet/
│       └── InlineDiffViewer.swift
└── Services/
    ├── CodexService.swift               — Thin wrapper over libsmithers Codex C API
    ├── JSONRPCTransport.swift           — Pipe-based JSON-RPC framing
    ├── SuggestionService.swift          — AI-generated workspace-aware suggestions
    └── ChatHistoryStore.swift           — SQLite-backed chat persistence
```

##### Features/IDE/

```
Features/IDE/
├── IDEWindowRootView.swift      — NavigationSplitView (sidebar + detail)
├── Sidebar/
│   ├── FileTreeSidebar.swift
│   ├── FileTreeRow.swift
│   └── FileTreeEmptyState.swift
├── Detail/
│   ├── IDEWorkspaceDetailView.swift
│   ├── IDETabBar.swift
│   ├── IDETabItem.swift
│   ├── BreadcrumbBar.swift
│   ├── IDEContentArea.swift
│   ├── IDEStatusBar.swift
│   └── IDEEmptyState.swift
├── DiffViewer/
│   └── DiffViewer.swift
└── Models/
    ├── FileItem.swift               — Recursive tree model
    ├── TabItem.swift                — Tab model (file/terminal/diff/webview/chat)
    ├── TabModel.swift               — Open tabs, selected tab, ordering
    ├── FileTreeModel.swift          — Root items, expansion, lazy loading
    └── EditorStateModel.swift       — Per-file view state
```

##### Other Feature directories follow the same pattern.

#### Helpers/

```
Helpers/
├── Extensions/                  — Swift extensions (NSColor+Hex, View+Theme, etc.)
├── DesignSystem/               — Tokens, AppTheme, shared components (IconButton, Badge, etc.)
└── Protocols.swift             — Shared protocols
```

#### Services/

```
Services/
├── AppModel.swift           — Composition root: the single @Observable god object
├── WorkspaceModel.swift     — Per-workspace state container
├── FileItem.swift           — Recursive tree model with lazy-loading sentinel pattern
├── ChatMessage.swift        — Message model (role, kind, images, timestamps, turn tracking)
├── ChatSession.swift        — Session metadata (id, title, creation date, last message preview)
├── ChatModel.swift          — Chat sessions, messages, streaming state (~250 lines)
├── TabItem.swift            — Tab model (id, kind: file/terminal/diff/webview, title, URL, modified flag)
├── TabModel.swift           — Open tabs, selected tab, tab ordering (~150 lines)
├── FileTreeModel.swift      — Root items, expansion state, lazy loading (~200 lines)
├── EditorStateModel.swift   — Per-file view state: scroll, selection, cursors (~100 lines)
├── DiffModels.swift         — DiffDocument, DiffFile, DiffHunk, DiffLine
├── JJModels.swift           — JJChange, JJFileDiff, JJStatus, JJBookmark, JJOperation, Snapshot
├── JJModel.swift            — Working copy, log, bookmarks, ops, snapshots (~100 lines)
├── AgentModels.swift        — AgentWorkspace, MergeQueueEntry, AgentStatus
├── AgentModel.swift         — Active agents, merge queue (~80 lines)
├── SkillModels.swift        — SkillItem, SkillScope, SkillFrontmatter, SkillDocument
├── SkillsModel.swift        — Installed/active/registry skills (~100 lines)
├── SearchModel.swift        — Query, results, preview (~80 lines)
├── SearchModels.swift       — SearchResult, SearchMatch, SearchPreview
├── EditorViewState.swift    — Per-file state struct: scroll position, selection range, cursor positions
├── CodexEvent.swift         — Event enum for AI backend communication
├── Preferences.swift        — All preference keys, defaults, range constants
└── Protocols.swift          — Shared protocols (Identifiable extensions, URL helpers)
```

#### Services/

External integrations. All async. Every service is a class (reference type) because they manage subprocess lifecycle, connections, and mutable caches.

```
Services/
├── CodexService.swift           — Thin wrapper over libsmithers Codex C API
├── JSONRPCTransport.swift       — Pipe-based JSON-RPC framing (newline-delimited)
├── CompletionService.swift      — AI code completion requests (debounced, streaming)
├── JJService.swift              — CLI wrapper for jj commands
├── JJSnapshotStore.swift        — SQLite persistence via GRDB
├── CommitStyleDetector.swift    — Analyzes recent commits for style matching
├── AgentOrchestrator.swift      — Parallel agent workspace management
├── SearchService.swift          — Ripgrep-based workspace search
├── SuggestionService.swift      — AI-generated workspace-aware prompt suggestions
├── SkillScanner.swift           — Discovers skills from filesystem
├── SkillRegistryClient.swift    — Fetches skills from remote registry
├── SkillInstaller.swift         — Downloads and installs skills
├── ChatHistoryStore.swift       — SQLite-backed chat persistence (GRDB)
├── SessionStore.swift           — Persists open tabs, selected file, sidebar state per workspace
├── WindowFrameStore.swift       — Per-workspace window frame persistence
├── IPCServer.swift              — Unix socket server for smithers-ctl
├── SmithersCtlInterpreter.swift — Parses and dispatches CLI commands
├── FileWatcher.swift            — FSEvents-based file system change monitoring
└── ServiceContainer.swift       — Holds all service instances, created by AppModel
```

#### DesignSystem/

Design tokens and shared SwiftUI components. No business logic.

```
DesignSystem/
├── Tokens/
│   ├── ColorTokens.swift    — Surface colors, semantic colors, chat colors, syntax palette
│   ├── Typography.swift     — Type scale, line height multipliers, font constructors
│   ├── Spacing.swift        — 4pt grid constants
│   ├── Radii.swift          — Corner radius scale
│   └── Shadows.swift        — Overlay shadow presets
├── Theme/
│   ├── AppTheme.swift       — Theme struct with all resolved NSColor/Color values
│   ├── ThemeEnvironment.swift — SwiftUI environment key for theme injection
│   └── ThemeDerived.swift   — Light theme derivation algorithm, Neovim derivation
├── Components/
│   ├── IconButton.swift     — Small/Medium/Large icon buttons with hover states
│   ├── PrimaryButton.swift  — Accent-colored action buttons
│   ├── PillButton.swift     — Capsule-shaped category pills
│   ├── Badge.swift          — Status badges (exit codes, applied/failed tags)
│   ├── Panel.swift          — Card/overlay container with border and radius
│   ├── SidebarListRow.swift — Reusable sidebar row (title, subtitle, trailing content)
│   ├── DividerLine.swift    — 1px themed separator
│   └── ToastView.swift      — Bottom-center auto-dismissing notification
└── Extensions/
    ├── NSColor+Hex.swift    — Hex parsing, luminance, blending
    └── View+Theme.swift     — Convenience modifiers for themed backgrounds, text
```

#### Editor/

Code editor subsystem. Uses STTextView, TreeSitter, and design tokens. Can access services (e.g., `CompletionService` for ghost text) and models directly.

```
Editor/
├── CodeEditorView.swift         — NSViewRepresentable wrapping STTextView
├── CodeEditorCoordinator.swift  — STTextViewDelegate, manages highlighting, cursors, ghost text
├── MultiCursorTextView.swift    — STTextView subclass with multi-cursor support
├── TreeSitterHighlighter.swift  — Async parse → attribute application pipeline
├── SupportedLanguages.swift     — Language registry (extension → TreeSitter language mapping)
├── EditorCursorView.swift       — Custom cursor rendering (bar/block/underline, blink)
├── EditorCursorGroupView.swift  — Manages multiple cursor views
├── GhostTextOverlayView.swift   — NSView overlay for AI completion previews
├── ScrollbarOverlayView.swift   — Custom scrollbar (always/automatic/never modes)
├── ScrollbarHostingView.swift   — Container for scroll view + scrollbar overlay
├── IndentGuidesView.swift       — Vertical indent guide lines
├── MinimapView.swift            — Zoomed-out code overview (right side)
└── BracketMatcher.swift         — Finds matching bracket pairs for highlighting
```

#### Terminal/

Ghostty terminal integration. Thin wrapper around the C library.

```
Terminal/
├── GhosttyApp.swift             — Singleton managing ghostty_app_t lifecycle
├── GhosttyTerminalView.swift    — NSView wrapping ghostty_surface_t
├── GhosttyInput.swift           — Keyboard event → ghostty key mapping
├── GhosttyFrameScheduler.swift  — Display link for frame rendering
└── TerminalConfiguration.swift  — Config string builder for Ghostty options
```

#### Neovim/

Neovim mode integration. Manages a subprocess and orchestrates bidirectional sync between the editor, file tree, tab model, and terminal.

```
Neovim/
├── NvimController.swift         — Subprocess lifecycle and RPC bridge
├── NvimRPC.swift                — MessagePack encoder/decoder
├── NvimExtUIOverlay.swift       — SwiftUI overlays for external UI (cmdline, popup, messages)
├── NvimFloatingWindowEffects.swift
├── NvimUIState.swift            — Observable state for Neovim UI
└── InputMethodSwitcher.swift    — Input source switching on mode change
```

#### Views/Chat/

Chat window view hierarchy.

```
Views/Chat/
├── ChatWindowRootView.swift     — NavigationSplitView (sidebar + detail)
├── Sidebar/
│   ├── ChatSidebarView.swift        — Container: mode bar + content switcher
│   ├── SidebarModeBar.swift         — Chats / Source / Agents toggle
│   ├── ChatSessionList.swift        — Grouped session list (Today/Yesterday/etc.)
│   ├── ChatSessionRow.swift         — Individual session row
│   ├── ChatSidebarSearchField.swift — Filter sessions
│   ├── JJPanelSidebar.swift         — Version control panel
│   └── AgentDashboardSidebar.swift  — Agent management panel
├── Detail/
│   ├── ChatDetailView.swift         — VStack: title bar + messages + composer
│   ├── ChatTitleBarZone.swift       — Workspace name + "Open Editor" button
│   ├── ChatMessagesZone.swift       — ScrollViewReader + LazyVStack of messages
│   ├── MessageBubbles/
│   │   ├── UserMessageBubble.swift
│   │   ├── AssistantMessageBubble.swift
│   │   ├── CommandBubble.swift
│   │   ├── DiffPreviewCard.swift
│   │   ├── StatusMessageBubble.swift
│   │   └── StarterPromptView.swift
│   ├── MessageHoverActionBar.swift  — Floating action bar on hover
│   ├── ChatComposerZone.swift       — Input field + attachments + send/interrupt
│   ├── AttachmentStrip.swift        — Horizontal thumbnail row
│   ├── FullscreenImageViewer.swift  — Overlay for viewing images
│   └── ChatWelcomeScreen.swift      — Empty state with AI-generated suggestions
└── DiffSheet/
    └── InlineDiffViewer.swift       — Sheet-presented diff viewer (for chat context)
```

#### Views/IDE/

IDE/workspace window view hierarchy.

```
Views/IDE/
├── IDEWindowRootView.swift      — NavigationSplitView (sidebar + detail)
├── Sidebar/
│   ├── FileTreeSidebar.swift
│   ├── FileTreeRow.swift
│   └── FileTreeEmptyState.swift
├── Detail/
│   ├── IDEWorkspaceDetailView.swift — VStack: tab bar + breadcrumbs + content + status bar
│   ├── IDETabBar.swift              — Horizontal scrolling tabs with drag reorder
│   ├── IDETabItem.swift             — Individual tab rendering
│   ├── BreadcrumbBar.swift          — File path segments
│   ├── IDEContentArea.swift         — Switches between editor/terminal/diff/webview
│   ├── IDEStatusBar.swift           — Bottom bar (line/col, language, skills, indentation)
│   └── IDEEmptyState.swift          — "Select a file to edit" placeholder
└── DiffViewer/
    └── DiffViewer.swift             — Unified diff display
```

#### Views/Overlays/

Overlays shared across windows or specific to the IDE.

```
Views/Overlays/
├── CommandPaletteView.swift     — Cmd+P fuzzy finder
├── SearchPanelView.swift        — Cmd+Shift+F workspace search
├── KeyboardShortcutsPanel.swift — Cmd+/ slide-in panel
└── ProgressBarView.swift        — Top-edge progress indicator
```

#### App/

App entry point, window coordination, and app-wide concerns.

```
App/
├── SmithersApp.swift            — @main, scene definitions, menu commands
├── WindowCoordinator.swift      — Creates, shows, hides, focuses workspace panel windows
├── CloseGuard.swift             — Unsaved changes prompts for tab/window/app close
├── TmuxKeyHandler.swift         — Ctrl+A prefix key system
├── SettingsView.swift           — Preferences window
└── UpdateController.swift       — Sparkle integration
```
