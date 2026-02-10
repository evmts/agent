# IDE Window Implementation

## 7. IDE Window

### 7.1 Root

```swift
struct IDEWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showCommandPalette = false
    @State private var showSearchPanel = false
    @State private var showShortcutsPanel = false

    var body: some View {
        NavigationSplitView {
            FileTreeSidebar()
        } detail: {
            IDEWorkspaceDetailView(
                showCommandPalette: $showCommandPalette,
                showSearchPanel: $showSearchPanel,
                showShortcutsPanel: $showShortcutsPanel
            )
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        .overlay { if showCommandPalette { CommandPaletteView(...) } }
        .overlay { if showSearchPanel { SearchPanelView(...) } }
    }
}
```

### 7.2 File tree

**Rendering:** `List(selection:)` + manual recursive `FileTreeRow` (NOT `OutlineGroup` — manual = lazy loading + indent control).

**Lazy loading:** Children start `nil` (unexpanded) or `[.lazyPlaceholder]` (loading). On expand → `FileTreeModel.expandFolder(item:)` loads on bg thread. Chevron rotates 90° `.rotationEffect` 0.15s ease-in-out.

**Row:** `HStack`: optional chevron (12pt, folders) → icon (16pt, colored) → name (11pt) → spacer → optional modified dot (5pt circle, accent).

**Selection:** Accent `Capsule` overlay 3pt wide, row height - 6pt, leading edge.

**Context menus:** `.contextMenu { }`. Folders: New File, New Folder, Copy Path, Reveal in Finder, Rename, Delete. Files: Copy Path, Reveal in Finder, Open in Terminal, Rename, Delete.

**Empty:** Centered `VStack`: folder icon, "No Folder Open", `PrimaryButton` "Open Folder...", "⌘⇧O" hint.

### 7.3 Tab bar

`IDETabBar` — horizontal `ScrollView(.horizontal)` of `IDETabItem`.

Background `surface2`. Geometry: 120-220pt width, 30pt height. If fits → distribute evenly. Selected: white@6% bg + 2pt accent underline capsule. Unselected: secondary text. Content: icon (colored) + filename (11pt) + modified dot (non-hover) OR close btn (hover). Drag reorder: `.draggable` + `.dropDestination` with insertion highlight. Middle-click = close. Context: Close, Close Others, Close All, Close to Right, Copy Path, Reveal in Finder, Reveal in Sidebar. Overflow: trailing ellipsis.circle menu.

**Tab types:** `.file(URL)`, `.terminal(id, title)`, `.diff(id, title)`, `.webview(id, title)`, `.chat(id, title)`. **Chat tabs first-class** — sub-agents, forks, any session opens as `.chat` tab. Main chat (pane 0) NOT a tab — window primary content. Others = tabs.

### 7.4 Breadcrumb

File tabs only. `HStack` path segments separated by `Image(systemName: "chevron.right")` 10pt tertiary. Last segment primary opacity, earlier tertiary.

### 7.5 Content area

`IDEContentArea` switches tab kind: `.file` → `CodeEditorView`, `.terminal` → `GhosttyTerminalView`, `.diff` → `DiffViewer`, `.webview` → `WebView`, `nil` → `IDEEmptyState`. Transition: `.opacity` 0.1s crossfade.

### 7.6 Status bar

22pt, `surface2` bg, 1px top divider. Left: `Ln X, Col Y | UTF-8 | LF` (mono 10pt, secondary). Center: skills indicator (click → popover). Right: language + "Spaces: 4" (10pt secondary).

### 7.7 Command palette (Cmd+P)

Overlay dark scrim `black@35%`. Panel centered 65% width (420-680px), 55% height (320-460px), radius 10, surface2.

Two-pane: results (left) + preview (right, first 20 lines).

**Modes:** Default = fuzzy file (recent edits, views, index). Command = prefix `>` triggers command list with icons + shortcuts.

**Fuzzy:** substring > subsequence. Highlight matches accent. Keys: arrows navigate, Enter opens, Esc dismisses. Animation: scale 0.97 + opacity, spring (0.25s, bounce 0.15) appear, 0.15s ease-in dismiss.

### 7.8 Search panel (Cmd+Shift+F)

Top slide-down 55% width (max 560px), 65% height (max 520px), surface2. Search field top. Results grouped by file, highlighted matches. Preview pane bottom (120-240px) with context. Click → open + scroll. Backed by `SearchService` spawning `rg`.

### 7.9 Shortcuts panel (Cmd+/)

Right slide-in 260-320pt. Surface2. Search top. Grouped: General, Tabs, Command Palette, Search, Neovim.
