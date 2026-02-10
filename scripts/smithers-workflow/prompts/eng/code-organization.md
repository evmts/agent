# Code Organization

## Philosophy

**Feature-based org** (Ghostty pattern). Code by feature, not layer. Chat → `Features/Chat/`, editor → `Features/Editor/`, etc. Makes features findable.

No complex module graph. Single Xcode app target, organized by dirs. Any file refs any other — intentional. Dir structure provides findability, not isolation.

**Principle:** "Not avoiding god object. Breaking into smaller, findable files." Single god object with modular file split = correct architecture.

## Directory Responsibilities

All within `macos/Sources/`. Files ref each other directly — no imports between dirs.

### App/

Entry point, window coordination, app-wide state.

```
App/
├── SmithersApp.swift            — @main, scenes, menu commands
├── AppModel.swift               — Composition root: single @Observable god object
├── WorkspaceModel.swift         — Per-workspace state
├── WindowCoordinator.swift      — Create, show, hide, focus workspace windows
├── CloseGuard.swift             — Unsaved changes prompts (tab/window/app close)
├── TmuxKeyHandler.swift         — Ctrl+A prefix system
└── UpdateController.swift       — Sparkle integration
```

### Ghostty/

Core libsmithers Swift wrapper (like Ghostty's dir). C FFI bridge.

```
Ghostty/
├── SmithersCore.swift          — Thin wrapper around libsmithers C API (Unmanaged/callbacks)
├── MockSmithersCore.swift      — Mock for parallel UI dev
└── Surface View/               — If needed for terminal surface mgmt
```

### Features/

Feature-based. Each dir contains views, models, feature logic.

#### Features/Chat/

```
Features/Chat/
├── Models/
│   ├── ChatMessage.swift        — Message (role, kind, images, timestamps, turns)
│   ├── ChatSession.swift        — Session metadata (id, title, creation, last preview)
│   └── ChatModel.swift          — Sessions, msgs, streaming (~250 lines)
├── Views/
│   ├── ChatWindowRootView.swift — NavigationSplitView (sidebar + detail)
│   ├── Sidebar/
│   │   ├── ChatSidebarView.swift, SidebarModeBar.swift, ChatSessionList.swift,
│   │   ├── ChatSessionRow.swift, ChatSidebarSearchField.swift
│   ├── Detail/
│   │   ├── ChatDetailView.swift, ChatTitleBarZone.swift, ChatMessagesZone.swift,
│   │   ├── MessageBubbles/ (User, Assistant, Command, Diff, Status)
│   │   ├── MessageHoverActionBar.swift, ChatComposerZone.swift,
│   │   ├── SlashCommandPopup.swift, MentionPopup.swift, ChatWelcomeScreen.swift
│   └── DiffSheet/InlineDiffViewer.swift
└── Services/
    ├── CodexService.swift               — Thin wrapper over libsmithers Codex C API (in-process)
    ├── JSONRPCTransport.swift           — JSON-RPC framing for non-Codex backends (Claude Code/OpenCode)
    ├── SuggestionService.swift          — AI-generated workspace suggestions
    └── ChatHistoryStore.swift           — SQLite chat persistence
```

#### Features/IDE/

```
Features/IDE/
├── IDEWindowRootView.swift      — NavigationSplitView (sidebar + detail)
├── Sidebar/ (FileTreeSidebar, FileTreeRow, FileTreeEmptyState)
├── Detail/
│   ├── IDEWorkspaceDetailView.swift, IDETabBar.swift, IDETabItem.swift,
│   ├── BreadcrumbBar.swift, IDEContentArea.swift, IDEStatusBar.swift, IDEEmptyState.swift
├── DiffViewer/DiffViewer.swift
└── Models/
    ├── FileItem.swift, TabItem.swift, TabModel.swift,
    ├── FileTreeModel.swift, EditorStateModel.swift
```

### Helpers/

```
Helpers/
├── Extensions/ (NSColor+Hex, View+Theme, etc.)
├── DesignSystem/ (Tokens, AppTheme, shared components: IconButton, Badge, etc.)
└── Protocols.swift
```

### Services/

External integrations. All async. Classes (ref types) — manage subprocess lifecycle, connections, caches.

```
Services/
├── CodexService.swift (in-process), JSONRPCTransport.swift (external providers), CompletionService.swift,
├── JJService.swift, JJSnapshotStore.swift, CommitStyleDetector.swift,
├── AgentOrchestrator.swift, SearchService.swift, SuggestionService.swift,
├── SkillScanner.swift, SkillRegistryClient.swift, SkillInstaller.swift,
├── ChatHistoryStore.swift, SessionStore.swift, WindowFrameStore.swift,
├── IPCServer.swift, SmithersCtlInterpreter.swift, FileWatcher.swift,
└── ServiceContainer.swift (holds all service instances, created by AppModel)
```

### DesignSystem/

Tokens + shared SwiftUI components. No business logic.

```
DesignSystem/
├── Tokens/ (ColorTokens, Typography, Spacing, Radii, Shadows)
├── Theme/ (AppTheme, ThemeEnvironment, ThemeDerived)
├── Components/ (IconButton, PrimaryButton, PillButton, Badge, Panel, SidebarListRow, DividerLine, ToastView)
└── Extensions/ (NSColor+Hex, View+Theme)
```

### Editor/

Code editor subsystem. STTextView, TreeSitter, design tokens. Access services (e.g., `CompletionService` for ghost text) + models.

```
Editor/
├── CodeEditorView.swift, CodeEditorCoordinator.swift, MultiCursorTextView.swift,
├── TreeSitterHighlighter.swift, SupportedLanguages.swift,
├── EditorCursorView.swift, EditorCursorGroupView.swift, GhostTextOverlayView.swift,
├── ScrollbarOverlayView.swift, ScrollbarHostingView.swift, IndentGuidesView.swift,
├── MinimapView.swift, BracketMatcher.swift
```

### Terminal/

Ghostty integration. Thin wrapper around C lib.

```
Terminal/
├── GhosttyApp.swift (singleton managing ghostty_app_t lifecycle)
├── GhosttyTerminalView.swift (NSView wrapping ghostty_surface_t)
├── GhosttyInput.swift (keyboard → ghostty key mapping)
├── GhosttyFrameScheduler.swift (display link for frame rendering)
└── TerminalConfiguration.swift (config string builder)
```

### Neovim/

Neovim mode. Subprocess + bidirectional sync (editor, file tree, tab model, terminal).

```
Neovim/
├── NvimController.swift (subprocess lifecycle + RPC bridge)
├── NvimRPC.swift (MessagePack encoder/decoder)
├── NvimExtUIOverlay.swift (SwiftUI overlays: cmdline, popup, messages)
├── NvimFloatingWindowEffects.swift, NvimUIState.swift, InputMethodSwitcher.swift
```

### Views/Chat/

Chat window view hierarchy.

```
Views/Chat/
├── ChatWindowRootView.swift
├── Sidebar/ (ChatSidebarView, SidebarModeBar, ChatSessionList, ChatSessionRow, ChatSidebarSearchField, JJPanelSidebar, AgentDashboardSidebar)
├── Detail/
│   ├── ChatDetailView.swift, ChatTitleBarZone.swift, ChatMessagesZone.swift,
│   ├── MessageBubbles/ (User, Assistant, Command, DiffPreview, Status, StarterPrompt)
│   ├── MessageHoverActionBar.swift, ChatComposerZone.swift, AttachmentStrip.swift,
│   ├── FullscreenImageViewer.swift, ChatWelcomeScreen.swift
└── DiffSheet/InlineDiffViewer.swift
```

### Views/IDE/

IDE/workspace window hierarchy.

```
Views/IDE/
├── IDEWindowRootView.swift
├── Sidebar/ (FileTreeSidebar, FileTreeRow, FileTreeEmptyState)
├── Detail/ (IDEWorkspaceDetailView, IDETabBar, IDETabItem, BreadcrumbBar, IDEContentArea, IDEStatusBar, IDEEmptyState)
└── DiffViewer/DiffViewer.swift
```

### Views/Overlays/

Shared or IDE-specific overlays.

```
Views/Overlays/
├── CommandPaletteView.swift (Cmd+P fuzzy finder)
├── SearchPanelView.swift (Cmd+Shift+F workspace search)
├── KeyboardShortcutsPanel.swift (Cmd+/ slide-in)
└── ProgressBarView.swift (top-edge progress)
```

### App/

Entry point, window coordination, app-wide concerns.

```
App/
├── SmithersApp.swift (@main, scenes, menus)
├── WindowCoordinator.swift (create, show, hide, focus workspace windows)
├── CloseGuard.swift (unsaved prompts: tab/window/app)
├── TmuxKeyHandler.swift (Ctrl+A prefix)
├── SettingsView.swift (preferences window)
└── UpdateController.swift (Sparkle)
```
