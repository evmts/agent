# Plan: IDE File Tree Sidebar Shell

## Ticket: ide-file-tree-shell

## Summary

Implement the FileTreeSidebar visual shell for the IDE window per design spec §6.2. This creates placeholder file tree rows with hover/selection states, wires the sidebar into `IDEWindowRootView` via `NavigationSplitView`, and adds unit tests. No real filesystem I/O — placeholder data only.

## Layers Touched

- **Swift** (UI views, unit tests, Xcode project)

## Design Spec References

- §6.2 — File tree sidebar (bg `surface1`, row height 28-32pt, 16pt indent, hover `white@4%`, selected capsule 3pt wide radius 2, current file `accent@6%` bg)
- §3.5 — SidebarListRow (reference only — FileTree uses different selection indicator: leading capsule bar, NOT full row fill)
- §6.1 — IDE root layout (`NavigationSplitView`, sidebar min:180/ideal:240/max:400)

## Existing Infrastructure

- **Design tokens**: `DS.Color.surface1`, `DS.Color.accent`, `DS.Color.chatSidebarHover` (= `white@4%`), `DS.Color.warning` (modified dot), `DS.Typography.s` (11pt), `DS.Space._16` (indent), `DS.Radius._2` (capsule)
- **AppTheme**: `theme.secondaryBackground` = `surface1` in dark mode, `theme.foreground`, `theme.accent`
- **Pattern**: `ChatWindowRootView` shows exact `NavigationSplitView` + sidebar pattern to follow
- **Components**: `DividerLine`, `IconButton` reusable; `SidebarListRow` is reference but NOT reused (different selection UI)

## Key Design Decisions

1. **DO NOT reuse SidebarListRow** — FileTree uses a leading 3pt accent capsule bar for selection, not full-row background fill like chat sidebar.
2. **Row height = 30pt** — spec says 28-32pt, 30pt is the sweet spot.
3. **Placeholder data only** — hardcoded sample file/folder items. No `FileTreeModel`, no filesystem, no `FileItem` model beyond a minimal local struct.
4. **Indent = 16pt per level** — per spec §6.2 tree indent.
5. **No chevron rotation animation yet** — static placeholder, chevrons shown but not interactive. Animation will come with real expand/collapse.

---

## Implementation Steps

### Step 0: Create directory structure

Create `macos/Sources/Features/IDE/Sidebar/` directory for the new file.

**Files:**
- Create directory `macos/Sources/Features/IDE/Sidebar/`

### Step 1: Write unit test (TDD — test first)

Create `FileTreeSidebarTests.swift` with:
- Compile-time API surface check: instantiate `FileTreeSidebar` and `FileTreeRow`
- Verify design token values used (e.g., `DS.Typography.s == 11`, row indent multiplier == 16pt)
- Accessibility identifier assertion (verify the string constants exist)

Register in Xcode project pbxproj (Tests build phase).

**Files:**
- Create: `macos/SmithersTests/FileTreeSidebarTests.swift`
- Modify: `macos/Smithers.xcodeproj/project.pbxproj` (PBXFileReference + PBXBuildFile + Tests group + Tests Sources phase)

### Step 2: Create FileTreeSidebar.swift

The main sidebar view with placeholder content. Contains:

**`FileTreeSidebar`** — Top-level view:
- `@Environment(\.theme)` for theming
- `VStack(spacing: 0)` root
- Root header (optional, 28pt, `surface2` bg, workspace name)
- `DividerLine()`
- Scrollable list of placeholder `FileTreeRow` items
- Background `surface1`
- `.accessibilityIdentifier("file_tree_sidebar")`

**`FileTreeRow`** — Individual row (private to file for now):
- Parameters: `name: String`, `iconName: String`, `iconColor: Color`, `isFolder: Bool`, `isExpanded: Bool`, `isSelected: Bool`, `level: Int`, `isModified: Bool`
- Height: 30pt
- Layout: `HStack` — leading indent (`level * 16pt`) + optional chevron (12pt, folders only) + icon (16pt, colored) + name (11pt, `.s`) + spacer + optional modified dot (6pt circle, `warning` color)
- Hover state: `@State private var hovering = false` + `.onHover { hovering = $0 }`
- Hover bg: `white@4%` (reuse `DS.Color.chatSidebarHover`)
- Selection: leading `Capsule` overlay, 3pt wide, `DS.Radius._2`, accent color, full row height minus 6pt vertical inset
- Current file: `accent@6%` background when selected
- `.accessibilityIdentifier("file_tree_row_\(name)")`
- `.buttonStyle(.plain)` wrapping

**Placeholder data:** ~8 items showing folder + file hierarchy:
```
▸ src/           (folder, expanded)
  ▸ build/       (folder, collapsed)
    main.zig     (file)
    lib.zig      (file, selected)
    storage.zig  (file, modified)
  ▸ pkg/         (folder, collapsed)
  include/       (folder)
  build.zig      (file)
```

Register in Xcode project pbxproj (App Sources phase + IDE/Sidebar group).

**Files:**
- Create: `macos/Sources/Features/IDE/Sidebar/FileTreeSidebar.swift`
- Modify: `macos/Smithers.xcodeproj/project.pbxproj` (PBXFileReference + PBXBuildFile + new Sidebar group under IDE + App Sources phase)

### Step 3: Upgrade IDEWindowRootView to NavigationSplitView

Replace the current stub `VStack` with `NavigationSplitView` following the `ChatWindowRootView` pattern:

```swift
NavigationSplitView {
    FileTreeSidebar()
} detail: {
    // Placeholder detail content (existing heading + workspace name)
}
.navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
```

Keep existing `.accessibilityIdentifier("ide_window_root")` on the outer container. Detail pane retains the current placeholder text for now (will be replaced by tab bar + editor in future tickets).

**Files:**
- Modify: `macos/Sources/Features/IDE/Views/IDEWindowRootView.swift`

### Step 4: Verify build passes

Run `zig build all` to confirm:
- Xcode project compiles with new files
- Unit tests pass
- Formatting checks pass

**Files:** (none created/modified — verification only)

---

## Xcode Project Changes (pbxproj detail)

### New IDs needed:

| Purpose | Type | ID |
|---------|------|----|
| FileTreeSidebar.swift file ref | PBXFileReference | `FTS0000000000000000001` |
| FileTreeSidebar.swift build file (app) | PBXBuildFile | `FTB0000000000000000001` |
| Sidebar group under IDE | PBXGroup | `FTG0000000000000000001` |
| FileTreeSidebarTests.swift file ref | PBXFileReference | `FTS0000000000000000002` |
| FileTreeSidebarTests.swift build file (tests) | PBXBuildFile | `FTB0000000000000000002` |

### Sections to modify:

1. **PBXFileReference** — Add entries for FileTreeSidebar.swift and FileTreeSidebarTests.swift
2. **PBXBuildFile** — Add build entries linking file refs to Sources phases
3. **PBXGroup** — Create new `Sidebar` group (`FTG0000000000000000001`) under IDE group (`E50000000000000000000005`), containing FileTreeSidebar.swift
4. **PBXGroup** — Add FileTreeSidebarTests.swift to Tests group (`B1111111111111111111111B`)
5. **PBXSourcesBuildPhase (App)** — Add `FTB0000000000000000001` to `A00000000000000000000007`
6. **PBXSourcesBuildPhase (Tests)** — Add `FTB0000000000000000002` to `B11111111111111111111113`

---

## Risks

1. **Xcode pbxproj manual edits** — Hand-editing project.pbxproj is fragile. Malformed entries break the entire project. Mitigation: follow exact patterns from existing entries (ChatSidebarView registration), verify build immediately.
2. **NavigationSplitView sidebar width interaction** — The `.navigationSplitViewColumnWidth` modifier applies to the sidebar column. Verify it doesn't conflict with window default sizing. Low risk — proven pattern in ChatWindowRootView.
3. **Existing UI test regression** — `WindowFlowTests.testOpenEditorFromChatTitleBarOpensIDE` checks for `ide_window_root` accessibility identifier. The refactored IDEWindowRootView must keep this identifier. Mitigation: explicitly preserve it.
4. **Swift 6 strict concurrency** — `@State` and `@Environment` in SwiftUI views are safe. FileTreeRow uses only value types and view-local state. Low risk.

---

## Test Plan

### Unit Tests (`FileTreeSidebarTests.swift`)

| Test | Description |
|------|-------------|
| `testFileTreeSidebar_APIInstantiates` | Compile-time check: construct `FileTreeSidebar()` |
| `testFileTreeRow_APIInstantiates` | Compile-time check: construct `FileTreeRow` with all parameters |
| `testFileTreeRow_indentMultiplier` | Verify indent constant is 16pt (`DS.Space._16`) |
| `testFileTreeRow_typographyToken` | Verify row text uses 11pt (`DS.Typography.s`) |
| `testFileTreeTokens_surfaceAndHover` | Verify `DS.Color.surface1` and `DS.Color.chatSidebarHover` have valid alpha |

### Existing UI Tests (must not regress)

| Test | File | Status |
|------|------|--------|
| `testOpenEditorFromChatTitleBarOpensIDE` | `WindowFlowTests.swift` | Must pass — checks `ide_window_root` identifier |
