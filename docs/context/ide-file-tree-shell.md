# Research Context: ide-file-tree-shell

## Summary

Implement `FileTreeSidebar` visual/interaction shell for the IDE window. The design system, token infrastructure, and component library are fully built. The IDE window exists as a stub (`IDEWindowRootView.swift`) — needs to be upgraded to `NavigationSplitView` with sidebar. The chat sidebar (`ChatSidebarView.swift` + `ChatWindowRootView.swift`) provides the exact pattern to follow. No real filesystem I/O — placeholder data only.

## Key Reference Files

### 1. IDEWindowRootView.swift (MODIFY — upgrade to NavigationSplitView)
- **Path:** `macos/Sources/Features/IDE/Views/IDEWindowRootView.swift`
- Currently a bare `VStack` with heading text — no sidebar
- Must become `NavigationSplitView { FileTreeSidebar() } detail: { ... }` like ChatWindowRootView
- Already has `accessibilityIdentifier("ide_window_root")`

### 2. ChatWindowRootView.swift (PATTERN — NavigationSplitView usage)
- **Path:** `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`
- Uses `NavigationSplitView` with `.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)`
- Design spec §6.1 says IDE sidebar: `min: 180, ideal: 240, max: 400`
- Pattern: sidebar view + detail view, both reading `@Environment(AppModel.self)` and `@Environment(\.theme)`

### 3. Components.swift — SidebarListRow (PATTERN — hover/selection)
- **Path:** `macos/Sources/Helpers/DesignSystem/Components.swift`
- `SidebarListRow` has hover (`white@4%`) and selected (`accent@12%`) states
- Uses `@State private var hovering = false` + `.onHover { hovering = $0 }`
- Uses `RoundedRectangle(cornerRadius: DS.Radius._6).fill(...)` for background states
- BUT: FileTree needs different selection indicator — **left capsule accent bar** (3pt width, per spec §6.2)

### 4. Tokens.swift (USE — design tokens)
- **Path:** `macos/Sources/Helpers/DesignSystem/Tokens.swift`
- Key tokens for file tree:
  - `DS.Color.surface1` (#141826) — file tree background per spec §6.2
  - `DS.Color.border` (white@8%) — separator lines
  - `DS.Color.chatSidebarHover` (white@4%) — hover bg (same token works for IDE sidebar)
  - `DS.Color.accent` (#4C8DFF) — selection capsule + expanded folder icon
  - `DS.Color.textPrimary/Secondary/Tertiary` — text opacities
  - `DS.Typography.s` (11pt) — row text per spec §6.2
  - `DS.Space._16` — indent per level per spec §6.2
  - Row height 28-32pt per spec §6.2

### 5. AppTheme.swift (USE — theme environment)
- **Path:** `macos/Sources/Helpers/DesignSystem/AppTheme.swift`
- Access pattern: `@Environment(\.theme) private var theme`
- `theme.secondaryBackground` = `DS.Color.surface1` in dark mode
- `theme.foregroundColor` for SwiftUI Color convenience

### 6. ComponentsTests.swift (PATTERN — test approach)
- **Path:** `macos/SmithersTests/ComponentsTests.swift`
- Pattern: `@MainActor final class ComponentsTests: XCTestCase`
- Tests instantiate views as compile-time surface checks: `_ = PrimaryButton(title: "Run", ...)`
- Tests verify token values exist: `XCTAssertGreaterThan(DS.Color.chatPillBg.alphaComponent, 0.0)`
- Tests verify ordering/contracts: `XCTAssertLessThan(DS.Typography.s, DS.Typography.base)`

### 7. Xcode Project (MODIFY — register new files)
- **Path:** `macos/Smithers.xcodeproj/project.pbxproj`
- IDE group: `E50000000000000000000005` contains `E50000000000000000000006 /* Views */`
- Views group: `E50000000000000000000006` currently only has `IDEWindowRootView.swift`
- Need to add: Sidebar subgroup + FileTreeSidebar.swift
- Need PBXBuildFile + PBXFileReference + group membership + Sources build phase entries
- Convention for IDs: hex-like strings (e.g., `F20000000000000000000002`)
- Tests go in `B11111111111111111111113` sources build phase

## Design Spec Requirements (§6.2)

### File Tree Appearance
- Background: `surface1`
- Root header: `surface2`
- Indent: 16pt per level, guides 1px `border@35%`
- Row height: 28-32pt

### Row Spec
- HStack: disclosure chevron (folders, 12pt) + file/folder icon (16pt, colored) + name (11pt) + spacer + modified dot (6pt, `color.warning`)
- **Hover:** `white@4%`
- **Selected:** accent Capsule 3pt width, radius 2, full height minus 6pt inset
- **Current file:** `accent@6%` bg + capsule

### Empty State (for later)
- Centered: folder icon + "No Folder Open" + "Open Folder..." button + "⌘⇧O" hint

### Keyboard Nav (for later)
- Arrows Up/Down, Right expand, Left collapse, Enter open, Space quick-look, Delete confirm

## V1 Prototype Reference Patterns

### FileTreeSidebar (prototype0)
- Path: `prototype0/Smithers/FileTreeSidebar.swift` (symlink to `../smithers/apps/desktop/Smithers/FileTreeSidebar.swift`)
- Uses `List(selection:)` + recursive `FileTreeRow`
- Manual recursion (NOT `OutlineGroup`) for lazy loading + indent control
- Row height: 26pt in v1
- Selection: left Capsule bar (2pt wide, 14pt height)
- Hover: `selectionBackgroundColor.opacity(0.4-0.5)` fill
- Chevron: rotates 90deg with `.animation(.easeInOut(duration: 0.15))`
- File icons: `iconForFile()` helper maps extensions to SF Symbols
- File colors: `colorForFile()` maps extensions to colors (Swift=orange, TS=blue, etc.)

### prototype1 (Next.js)
- Path: `prototype1/components/smithers/file-tree.tsx`
- Row height: 28px
- Selection indicator: 3px left bar with `var(--sm-accent)`, `borderRadius: "0 2px 2px 0"`
- Hover: `rgba(255,255,255,0.04)` background
- Indent guides: 1px lines at each level, `rgba(255,255,255,0.035)`

## Implementation Plan

### Files to Create
1. `macos/Sources/Features/IDE/Sidebar/FileTreeSidebar.swift` — main sidebar view with placeholder rows
2. `macos/SmithersTests/FileTreeSidebarTests.swift` — instantiation + accessibility test

### Files to Modify
1. `macos/Sources/Features/IDE/Views/IDEWindowRootView.swift` — upgrade to NavigationSplitView
2. `macos/Smithers.xcodeproj/project.pbxproj` — register new files + create Sidebar group

### Key Implementation Details

**FileTreeSidebar pattern (placeholder, no real FS):**
```swift
struct FileTreeSidebar: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Placeholder rows with hover + selection
            FileTreeRow(name: "src", isFolder: true, isExpanded: true, level: 0)
            FileTreeRow(name: "main.zig", isFolder: false, level: 1, isSelected: true)
            FileTreeRow(name: "build.zig", isFolder: false, level: 0)
            Spacer()
        }
        .background(Color(nsColor: theme.secondaryBackground)) // surface1
        .accessibilityIdentifier("file_tree_sidebar")
    }
}
```

**Selection capsule (per spec §6.2):**
```swift
.overlay(alignment: .leading) {
    if isSelected {
        Capsule()
            .fill(Color(nsColor: DS.Color.accent))
            .frame(width: 3, height: rowHeight - 6)
    }
}
```

**IDEWindowRootView upgrade:**
```swift
NavigationSplitView {
    FileTreeSidebar()
} detail: {
    // existing content
}
.navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
```

## Gotchas / Pitfalls

1. **Xcode project registration is manual.** Must add PBXBuildFile, PBXFileReference, group membership, AND Sources build phase entry. Missing any one = file not compiled. The Sidebar subdirectory also needs a new PBXGroup.

2. **Don't use `OutlineGroup`** — spec and v1 both use manual recursive rows for control over lazy loading, indent guides, and row chrome. For the shell, flat placeholder rows are fine.

3. **Selection capsule != SidebarListRow.** The existing `SidebarListRow` uses `chatSidebarSelected` fill for the whole row bg. The IDE file tree uses a different pattern: a leading capsule bar (3pt wide) per §6.2. Don't reuse `SidebarListRow` — create a new `FileTreeRow`.

4. **`@MainActor` on tests.** All tests that touch `@Observable @MainActor` models must be `@MainActor`. The test pattern uses `@MainActor final class XTests: XCTestCase`.

5. **NavigationSplitView sidebar width.** IDE uses different constraints than chat: `min: 180, ideal: 240, max: 400` (vs chat's `min: 200, ideal: 260, max: 360`).
