# State Architecture

## Overview

v2 uses `@Observable` (not Combine `ObservableObject`+`@Published`). SwiftUI tracks per-view property reads, invalidates only when those change.

## Model Graph

```
AppModel (@Observable, @MainActor)
├── workspace: WorkspaceModel?           — nil until folder opened (single for MVP)
├── chat: ChatModel                      — works WITHOUT workspace
│   ├── sessions, messages, streaming state
│   └── suggestions: [SuggestedPrompt]   — AI-generated, workspace-aware
├── preferences: PreferencesModel        — all settings → UserDefaults
├── theme: AppTheme                      — resolved tokens (from prefs + optional nvim override)
├── windowCoordinator: WindowCoordinator — manages workspace panel window
└── services: ServiceContainer
    ├── codex: CodexService?, completion: CompletionService?
    ├── suggestion: SuggestionService    — generates workspace-aware prompts
    ├── jj: JJService?                   — bundled binary from app bundle
    ├── snapshotStore: JJSnapshotStore?, agentOrchestrator: AgentOrchestrator?
    ├── searchService: SearchService, chatHistory: ChatHistoryStore
    ├── sessionStore: SessionStore, windowFrames: WindowFrameStore
    ├── ipcServer: IPCServer, skillScanner: SkillScanner
    └── nvim: NvimController?            — nil unless nvim mode active

WorkspaceModel (@Observable, @MainActor)
├── rootDirectory: URL
├── fileTree: FileTreeModel              — root items, expansion, lazy loading
├── tabs: TabModel                       — open tabs, selected, ordering (EVERYTHING = tab)
├── editorState: EditorStateModel        — per-file (scroll, selection, cursors)
├── jj: JJModel                          — working copy, log, bookmarks, ops, snapshots
├── agents: AgentModel                   — active agents, merge queue
├── skills: SkillsModel                  — installed, active, registry cache
└── search: SearchModel                  — query, results, preview
```

## Key Decisions

1. **Chat = global, not per-workspace.** Works without workspace. Sessions reference workspace but not tied. Workspace-aware but standalone.
2. **Single workspace MVP.** `workspace: WorkspaceModel?` (0 or 1). Expands to `workspaces: [WorkspaceModel]` later.
3. **Everything = tab.** Files, terminals, chats, diffs, webviews — all `TabModel`. Detach/attach to windows.
4. **AI-generated suggestions.** Welcome prompts NOT hardcoded. `SuggestionService` generates from workspace context.
5. **Bundled deps.** `codex-app-server` + `jj` built from source, shipped in `.app` bundle.

## AppModel — Composition Root

```swift
@Observable @MainActor
final class AppModel {
    var workspace: WorkspaceModel?       // nil until folder opened
    var chat: ChatModel, preferences: PreferencesModel, theme: AppTheme
    let windowCoordinator: WindowCoordinator, services: ServiceContainer

    var hasWorkspace: Bool { workspace != nil }
    var workspaceName: String { workspace?.rootDirectory.lastPathComponent ?? "Smithers" }

    func openDirectory(_ url: URL) async { ... }
    func closeWorkspace() { ... }
    func showInEditor(fileURL: URL, line: Int?, column: Int?) { ... }
}
```

Created once in `SmithersApp.init()`, injected via SwiftUI environment to all windows.

## WorkspaceModel — Per-Workspace State

Created on directory open. Destroyed on close. Does NOT contain chat.

```swift
@Observable @MainActor
final class WorkspaceModel: Identifiable {
    let id = UUID(), rootDirectory: URL
    let fileTree: FileTreeModel, tabs: TabModel, editorState: EditorStateModel
    let jj: JJModel, agents: AgentModel, skills: SkillsModel, search: SearchModel
}
```

### Sub-Models

**FileTreeModel** (~200 LOC):
`items: [FileItem]`, `expandFolder(item:)`, `collapseFolder(item:)`, `reloadTree()`, `modifiedFiles: Set<URL>`

**TabModel** (~200 LOC) — everything = tab (files, terminals, diffs, webviews, sub-chats):
`openTabs: [TabItem]`, `selectedTab: TabItem?`
`openFile(_:)`, `closeTab(_:)`, `closeOtherTabs(keeping:)`, `reorderTab(from:to:)`
`openTerminal(id:title:)`, `openDiff(id:title:)`, `openChat(id:title:)`, `openWebview(id:url:title:)`
`detachTab(_:)`, `attachTab(_:)`

**EditorStateModel** (~100 LOC):
`viewStates: [URL: EditorViewState]`, `activeFileContent: String`, `activeLanguage: SupportedLanguage?`, `isLoading: Bool`

**ChatModel** (~300 LOC) — lives on AppModel, not WorkspaceModel. Main chat = orchestrator:
`sessions: [ChatSession]`, `selectedSession: ChatSession?`, `messages: [ChatMessage]`
`isTurnInProgress: Bool`, `streamingMessageId: UUID?`
`composerText: String`, `composerAttachments: [ChatImage]`, `suggestions: [SuggestedPrompt]`
`activeAgentChats: [AgentChatHandle]`
`sendMessage()`, `appendDelta(text:toMessage:)`, `interruptTurn()`, `spawnAgent(task:)`

**Main chat (orchestrator) vs sub-agents:**
- Main (pane 0) = user assistant, full context
- Sub-agents = ephemeral background workers, no human-in-loop, run to completion
- Human-in-loop: sub-agent "needs input" → orchestrator surfaces question → user responds → new sub-agent spawned
- Sub-agents unhideable as `.chat` tabs in workspace panel

**JJModel** (~100 LOC):
`isAvailable`, `modifiedFiles`, `changeLog`, `bookmarks`, `operations`, `snapshots`, `conflicts`, `refresh()`

**AgentModel** (~80 LOC):
`activeAgents: [AgentWorkspace]`, `mergeQueue: [MergeQueueEntry]`, `createAgent(task:)`, `cancelAgent(id:)`, `processQueue()`

**SkillsModel** (~100 LOC):
`installedSkills`, `activeSkills`, `registrySkills`, `toggleSkill(_:)`, `installSkill(_:)`, `scanWorkspace()`

**SearchModel** (~80 LOC):
`query`, `results`, `isSearching`, `selectedResult`, `preview`, `search()` (debounced)

## Window-Local UI State

Per-window ephemeral `@State` (not persisted):
**Chat:** `sidebarMode`, `sidebarSearchQuery`, `hoveredMessageId`, `showImageViewer`, `viewedImage`
**Workspace:** `showCommandPalette`, `showSearchPanel`, `showShortcutsPanel`, `commandPaletteQuery`, `isSidebarCollapsed`

## Persistence

SQLite (GRDB.swift) = primary layer.

| Data | Storage | When |
|------|---------|------|
| Preferences | UserDefaults | Immediate on change |
| Window frames | UserDefaults | 250ms debounce post resize/move |
| Chat sessions+messages | SQLite `~/Library/Application Support/Smithers/smithers.db` | 1s debounce |
| Thread IDs | SQLite (sessions) | On creation |
| Open tabs+sidebar widths | SQLite (keyed by workspace path) | Workspace close / app quit |
| JJ snapshots | SQLite (snapshots) | On creation |
| Scheduled agents | SQLite (schedules) | On create/edit |
| Per-file editor state | In-memory dict | NOT persisted |
| Chat images | File `~/Library/Application Support/Smithers/images/<hash>` | On attach |

## Cross-Window Reactivity

All windows observe same `AppModel`. AI appends message → only chat re-renders (workspace doesn't read `messages`).

AI changes file:
1. `ChatModel` appends `DiffPreviewCard` → chat re-renders
2. If `preferences.autoOpenIDEOnFileChange` → `AppModel.showInEditor()` called
3. `WindowCoordinator` ensures workspace panel visible
4. `TabModel` opens/selects file tab → workspace re-renders
5. `EditorStateModel.scrollToLine` set → editor animates

No explicit cross-window messaging. Shared model = communication channel.

## Agent Workspaces

Single user workspace, but `AgentOrchestrator` creates parallel agent workspaces via `jj workspace add` — lightweight working copies, shared repo history, independent file trees.

Agent workspaces NOT full `WorkspaceModel` — managed internally by `AgentOrchestrator`, visualized via agent dashboard. Work enters merge queue, merged into user workspace when complete.
