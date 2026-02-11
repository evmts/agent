# Context: chat-window-shell

Research context for implementing ChatWindowRootView per spec sections 5.1-5.4.

## Critical Finding: Xcode Project File Incomplete

**The `.pbxproj` only references `SmithersApp.swift` in its Sources build phase.** All other Swift files (AppModel.swift, Tokens.swift, Components.swift, AppTheme.swift, NSColor+Hex.swift, SmithersCore.swift) exist on disk but are NOT in the Xcode project. The build currently fails via `xcodebuild` with "cannot find 'AppModel' in scope".

**Every new Swift file MUST be added to `macos/Smithers.xcodeproj/project.pbxproj`** in:
1. `PBXFileReference` section — file reference
2. `PBXBuildFile` section — build file reference pointing to file ref
3. `PBXGroup` section — add to appropriate group's `children` array
4. `PBXSourcesBuildPhase` section — add build file ref to app target's Sources files list

The test target (`SmithersTests`) uses `@testable import Smithers` but also needs `TEST_HOST` and `BUNDLE_LOADER` configured, or test files need to be added to the test Sources build phase. Currently only `SmithersTests.swift` is in the test Sources phase, but `DesignSystemTests.swift` and `ComponentsTests.swift` also exist on disk unreferenced.

**This is the #1 blocker for the ticket.** The implementer must fix the project file to include ALL existing + new Swift files before anything will compile via `xcodebuild`.

## Existing Codebase State

### Files that exist and need Xcode project references:

**Already on disk, need `.pbxproj` entries:**
- `macos/Sources/App/SmithersApp.swift` (already in project)
- `macos/Sources/App/AppModel.swift` (NOT in project)
- `macos/Sources/Helpers/DesignSystem/Tokens.swift` (NOT in project)
- `macos/Sources/Helpers/DesignSystem/AppTheme.swift` (NOT in project)
- `macos/Sources/Helpers/DesignSystem/Components.swift` (NOT in project)
- `macos/Sources/Helpers/Extensions/NSColor+Hex.swift` (NOT in project)
- `macos/Sources/Ghostty/SmithersCore.swift` (NOT in project)

**Test files needing project references:**
- `macos/SmithersTests/SmithersTests.swift` (in project)
- `macos/SmithersTests/DesignSystemTests.swift` (NOT in project)
- `macos/SmithersTests/ComponentsTests.swift` (NOT in project)

### Empty directories awaiting new files:
- `macos/Sources/Features/Chat/Views/` (empty)
- `macos/Sources/Features/IDE/Views/` (empty)

## Current AppModel (minimal)

```swift
// macos/Sources/App/AppModel.swift
@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
}
```

Ticket needs to add workspace name and window coordinator stub properties.

## Current SmithersApp.swift (placeholder views)

ChatWindowRootView and IDEWindowRootView are currently inline placeholders in SmithersApp.swift (lines 39-61). The ticket replaces ChatWindowRootView with the real NavigationSplitView implementation in `Features/Chat/Views/ChatWindowRootView.swift`.

## Design System Already Implemented

All needed tokens exist in `DS.Color`, `DS.Typography`, `DS.Space`, `DS.Radius`. Key tokens for chat window:

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Color.chatSidebarBg` | `#0C0E16` | Sidebar background |
| `DS.Color.chatSidebarSelected` | `accent@12%` | Selected session |
| `DS.Color.chatSidebarHover` | `white@4%` | Hover state |
| `DS.Color.chatPillBg` | `white@6%` | Mode bar pill bg |
| `DS.Color.chatPillActive` | `accent@15%` | Active mode pill |
| `DS.Color.chatBubbleUser` | `accent@12%` | User message bubble |
| `DS.Color.chatBubbleAssistant` | `white@5%` | Assistant bubble |
| `DS.Color.chatInputBg` | `white@6%` | Composer bg |
| `DS.Color.titlebarBg` | `= surface1` | Title bar bg |
| `DS.Color.titlebarFg` | `white@70%` | Title bar text |
| `DS.Typography.chatSidebarTitle` | `12` | Session title size |
| `DS.Typography.chatTimestamp` | `10` | Timestamp size |
| `DS.Typography.base` | `13` | Message body size |
| `DS.Typography.chatHeading` | `28` | Welcome heading |
| `DS.Typography.s` | `11` | Status bar, sidebar |

Components available: `IconButton`, `PrimaryButton`, `PillButton`, `SidebarListRow`.

AppTheme provides `backgroundColor`, `foregroundColor` Color properties + NSColor versions for all tokens.

## v1 Reference Patterns (prototype0/)

### Return/Shift+Return — No Special Code Needed!
```swift
// prototype0/Smithers/ChatView.swift, lines 565-574
TextField("Message...", text: $workspace.chatDraft, axis: .vertical)
    .textFieldStyle(.plain)
    .lineLimit(1...4)
    .focused($inputFocused)
    .onSubmit {
        workspace.sendChatMessage()
    }
```
SwiftUI's `TextField(axis: .vertical)` with `.lineLimit(1...4)` handles:
- **Return** → triggers `.onSubmit` (sends message)
- **Shift+Return** → inserts newline (built-in TextField behavior)

### LazyVStack Message List
```swift
// prototype0/Smithers/ChatView.swift, lines 509-544
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(alignment: .center, spacing: 8) {
            ForEach(workspace.chatMessages) { message in
                ChatBubble(message: message, ...)
                    .id(message.id)
            }
        }
    }
    .onChange(of: chatMessages.count) { _, _ in
        // Auto-scroll to bottom
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
        }
    }
}
```

### Sidebar Mode Bar
```swift
// prototype0/Smithers/ContentView.swift, lines 2476-2532
HStack(spacing: 0) {
    sidebarButton(icon: "doc.text", label: "Files", isActive: ...) { ... }
    sidebarButton(icon: "arrow.triangle.branch", label: "Source", isActive: ...) { ... }
    sidebarButton(icon: "person.3", label: "Agents", isActive: ...) { ... }
}
.padding(.horizontal, 8)
.padding(.vertical, 4)
```
Per design spec: icons are `bubble.left.and.bubble.right` (Chats), `arrow.triangle.branch` (Source), `person.3` (Agents).

### Bubble Corner Radii (UnevenRoundedRectangle)
```swift
// User: trailing, tail at bottom-right
UnevenRoundedRectangle(topLeading: 12, bottomLeading: 12, bottomTrailing: 4, topTrailing: 12)
// Assistant: leading, tail at bottom-left
UnevenRoundedRectangle(topLeading: 12, bottomLeading: 4, bottomTrailing: 12, topTrailing: 12)
```

## Prototype1 Layout Reference

### Component Hierarchy
```
ChatWindow (flex h-full flex-col)
├── Title Bar (40px height)
│   ├── Center: workspace name (11pt, titlebar.fg)
│   └── Trailing: "Open Editor" IconButton
├── Sidebar (260px width)
│   ├── Mode Bar (40px height)
│   │   └── 3 buttons: Chats | Source | Agents
│   └── Content: session list (grouped by time)
└── Chat Detail (flex-1 flex-col)
    ├── Messages (flex-1 overflow-y-auto, LazyVStack gap-3 px-4 py-4)
    └── Composer (shrink-0)
        ├── TextField (multiline, 1-4 rows)
        ├── Action buttons: Attach, @Mention, Skills (left)
        └── Send button (32x32, accent, right)
```

### CSS Token Mapping (prototype1 → Swift)
- `--sm-sidebar-bg` → `DS.Color.chatSidebarBg`
- `--sm-sidebar-selected` → `DS.Color.chatSidebarSelected`
- `--sm-bubble-user` → `DS.Color.chatBubbleUser` / `theme.chatUserBubble`
- `--sm-bubble-assistant` → `DS.Color.chatBubbleAssistant` / `theme.chatAssistantBubble`
- `--sm-input-bg` → `DS.Color.chatInputBg` / `theme.inputFieldBackground`
- `--sm-titlebar-bg` → `DS.Color.titlebarBg`
- `--sm-accent` → `DS.Color.accent` / `theme.accent`

## Spec Requirements (§5.1-5.4)

### 5.1 Layout
- Root: `NavigationSplitView` — sidebar 200–360pt (default 260pt), detail flexible

### 5.2 Sidebar
- Mode bar: 40pt height, 8pt padding, `chat.sidebar.bg`
- 3 modes: Chats (`bubble.left.and.bubble.right`), Source (`arrow.triangle.branch`), Agents (`person.3`)
- Selected: accent text + `accent@12%` pill (radius 8)
- Inactive: secondary text, no bg
- For this ticket: stub content (placeholder lists)

### 5.3 Detail View
- Title bar: 28pt, `titlebar.bg`, centered workspace name 11pt, trailing Open Editor IconButton
- Messages: `ScrollViewReader` + `ScrollView` + `LazyVStack(spacing: 10-12)`, padding 16pt h / 16pt top / 12pt bottom
- Placeholder bubbles sufficient

### 5.4 Composer
- Container: radius 10, `chat.input.bg`, border 1px `white@6%`, padding 10pt
- TextField multiline 1–4 lines
- Send button: 32×32, radius 6, accent solid, arrow.up icon
- Return = submit, Shift+Return = newline

## Gotchas/Pitfalls

1. **Xcode project must be updated** — ALL existing + new files need PBXFileReference, PBXBuildFile, PBXGroup, and PBXSourcesBuildPhase entries. Without this, `xcodebuild` fails. This is the #1 risk.

2. **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY = complete` is set. All @Observable models need `@MainActor`. Closures crossing actor boundaries need `@Sendable` or `nonisolated`.

3. **NavigationSplitView column width** — Use `.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)` on the sidebar content, not the NavigationSplitView itself.

4. **Theme environment injection** — Already wired in SmithersApp: `.environment(\.theme, appModel.theme)`. All child views access via `@Environment(\.theme) private var theme`.

5. **UnevenRoundedRectangle** requires macOS 14+ (Sonoma) — available since we target macOS 14.

## Files to Create

1. `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — NavigationSplitView root
2. `macos/Sources/Features/Chat/Views/ChatSidebarView.swift` — Sidebar with mode bar + stub content
3. `macos/Sources/Features/Chat/Views/SidebarModeBar.swift` — Chats/Source/Agents buttons
4. `macos/Sources/Features/Chat/Views/ChatDetailView.swift` — Title + Messages + Composer
5. `macos/Sources/Features/Chat/Views/ChatMessagesZone.swift` — ScrollView + LazyVStack with placeholders
6. `macos/Sources/Features/Chat/Views/ChatComposerZone.swift` — TextField + Send button
7. `macos/Sources/Features/Chat/Views/ChatTitleBarZone.swift` — 28pt title bar with Open Editor

## Files to Modify

1. `macos/Sources/App/SmithersApp.swift` — Remove inline ChatWindowRootView placeholder (move to Features/Chat/)
2. `macos/Smithers.xcodeproj/project.pbxproj` — Add ALL files to project

## Open Questions

1. **How to properly fix the .pbxproj?** The project file is hand-crafted with manual UUIDs (A000..., B111...). Adding files requires generating unique IDs. The existing pattern uses readable hex IDs. Need to follow the same pattern or use standard 24-char hex UUIDs.

2. **Test target setup** — SmithersTests uses `@testable import Smithers` but the test target lacks `TEST_HOST` / `BUNDLE_LOADER` settings. Tests may not compile even after fixing the main target. Need to add these settings or restructure.

3. **`zig build all` does NOT run `xcodebuild`** — The canonical green check (`zig build all`) currently doesn't include xcode-test. The `xcode-test` step exists but isn't wired into `all`. Acceptance criteria says "zig build xcode-test passes" which currently fails. May need to be addressed as part of this ticket or documented as pre-existing.
