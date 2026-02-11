# Plan: chat-window-shell — Scaffold Chat Window with NavigationSplitView and Composer Shell

## Summary

Implement ChatWindowRootView per spec §5.1–5.4: NavigationSplitView with sidebar (mode bar, stub content), title bar, messages zone (LazyVStack placeholder bubbles), and composer (multiline TextField + Send button). Replace inline placeholder in SmithersApp.swift. Fix Xcode project to include all existing + new files.

## Prerequisites

- Design system tokens, theme, and components already exist and are tested
- AppModel exists (minimal — needs workspace name stub)
- SmithersApp.swift has placeholder ChatWindowRootView to replace
- Xcode project file only references SmithersApp.swift — all other files missing

## Critical Blocker: Xcode Project File

The `.pbxproj` only has SmithersApp.swift in Sources build phase. 6 existing files + 7 new files + 2 test files must be registered. This is Step 0 — nothing else works without it.

UUID convention: existing project uses readable hex (A000... for app, B111... for tests). New entries will use C222... prefix for Chat feature files, D333... for new test files, E444... for existing files being added.

---

## Implementation Steps

### Step 0: Fix Xcode project — add ALL existing files to .pbxproj

**Why first:** Nothing compiles via xcodebuild until this is done. The 6 existing Swift files on disk are invisible to the build.

**Files to register in app target:**
- `Sources/App/AppModel.swift`
- `Sources/Helpers/DesignSystem/Tokens.swift`
- `Sources/Helpers/DesignSystem/AppTheme.swift`
- `Sources/Helpers/DesignSystem/Components.swift`
- `Sources/Helpers/Extensions/NSColor+Hex.swift`
- `Sources/Ghostty/SmithersCore.swift`

**Files to register in test target:**
- `SmithersTests/DesignSystemTests.swift`
- `SmithersTests/ComponentsTests.swift`

**For each file, add entries to 4 sections:**
1. `PBXFileReference` — file ref with path + type
2. `PBXBuildFile` — build file ref → file ref
3. `PBXGroup` — add to correct group's children (create Helpers, DesignSystem, Extensions, Ghostty, Features groups)
4. `PBXSourcesBuildPhase` — add build file to correct target's Sources

**Also needed for test target:**
- Add `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Smithers.app/Contents/MacOS/Smithers"` and `BUNDLE_LOADER = "$(TEST_HOST)"` to SmithersTests build configurations so `@testable import Smithers` resolves.

**Verify:** `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers -configuration Debug` compiles.

**Modify:** `macos/Smithers.xcodeproj/project.pbxproj`

---

### Step 1: Add workspace name stub to AppModel

**Why:** ChatTitleBarZone needs `appModel.workspaceName` to display centered title per spec §5.3.1.

**Changes:**
```swift
@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
    var workspaceName: String = "Smithers"  // stub — replaced when workspace opens
}
```

Simple one-line addition. No window coordinator yet (no-op stub for "Open Editor" lives in the view).

**Modify:** `macos/Sources/App/AppModel.swift`

---

### Step 2: Create SidebarModeBar.swift

**Why:** Smallest leaf component, no dependencies on other new views. Per spec §5.2.1.

**File:** `macos/Sources/Features/Chat/Views/SidebarModeBar.swift`

**Spec:** 40pt height, 8pt padding, `chat.sidebar.bg` background. 3 ModeBarItemButtons:
- Chats: `bubble.left.and.bubble.right`
- Source: `arrow.triangle.branch`
- Agents: `person.3`

Selected = accent text + `accent@12%` pill (radius 8). Inactive = secondary text, no bg. Hover = `white@4%`.

**Types needed:**
```swift
enum SidebarMode: String, CaseIterable {
    case chats, source, agents

    var icon: String { ... }
    var label: String { ... }
}
```

**Binding:** Takes `@Binding var mode: SidebarMode`.

---

### Step 3: Create ChatSidebarView.swift

**Why:** Contains SidebarModeBar + stub content panels. Per spec §5.2.

**File:** `macos/Sources/Features/Chat/Views/ChatSidebarView.swift`

**Structure:**
```
VStack(spacing: 0) {
    SidebarModeBar(mode: $sidebarMode)
    Divider()
    // Stub content for each mode
    switch sidebarMode {
    case .chats: placeholder session list (3 fake rows using SidebarListRow)
    case .source: Text("Source") placeholder
    case .agents: Text("Agents") placeholder
    }
}
.background(Color(nsColor: DS.Color.chatSidebarBg))
```

Uses `@State private var sidebarMode: SidebarMode = .chats`.

Sidebar sets `.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)`.

---

### Step 4: Create ChatTitleBarZone.swift

**Why:** Leaf component for detail header. Per spec §5.3.1.

**File:** `macos/Sources/Features/Chat/Views/ChatTitleBarZone.swift`

**Spec:** 28pt height, `titlebar.bg`. HStack: leading spacer, center workspace name 11pt `titlebar.fg`, trailing Open Editor IconButton (`rectangle.split.2x1`).

**"Open Editor" button:** Calls a closure `onOpenEditor: () -> Void` passed in. In this ticket, parent passes a no-op `{ }` or prints a log. Acceptance criteria says "hook (no-op or calls coordinator stub)".

---

### Step 5: Create ChatComposerZone.swift

**Why:** Independent leaf component. Per spec §5.4.

**File:** `macos/Sources/Features/Chat/Views/ChatComposerZone.swift`

**Structure:**
```
VStack(spacing: 8) {
    // Composer container
    VStack(spacing: 0) {
        TextField("Message...", text: $composerText, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .padding(DS.Space._10)
            .onSubmit { handleSend() }
    }
    .background(RoundedRectangle(cornerRadius: DS.Radius._10)
        .fill(Color(nsColor: theme.inputFieldBackground)))
    .overlay(RoundedRectangle(cornerRadius: DS.Radius._10)
        .strokeBorder(Color(nsColor: DS.Color.overlayWhite06), lineWidth: 1))

    // Footer: hint text left, Send button right
    HStack {
        Text("Return to send, Shift+Return for new line")
            .font(.system(size: DS.Typography.xs))
            .foregroundStyle(Color(nsColor: DS.Color.textTertiary))
        Spacer()
        // Send button 32x32, accent, arrow.up
        Button(action: handleSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: DS.Radius._6)
                    .fill(Color(nsColor: theme.accent).opacity(composerText.isEmpty ? 0.45 : 0.90)))
                .foregroundStyle(Color(nsColor: DS.Color.onAccentText))
        }
        .buttonStyle(.plain)
        .disabled(composerText.isEmpty)
    }
}
.padding(.horizontal, DS.Space._16)
.padding(.bottom, DS.Space._12)
```

**State:** `@State private var composerText: String = ""`

**handleSend():** Prints to os_log or clears text (stub). Trims whitespace, checks non-empty.

**Return/Shift+Return:** SwiftUI `TextField(axis: .vertical)` with `.onSubmit` handles this natively — Return triggers onSubmit, Shift+Return inserts newline. No custom keyboard code needed (confirmed by v1 prototype pattern).

---

### Step 6: Create ChatMessagesZone.swift

**Why:** Messages area with placeholder bubbles. Per spec §5.3.2.

**File:** `macos/Sources/Features/Chat/Views/ChatMessagesZone.swift`

**Structure:**
```
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(spacing: 12) {
            ForEach(placeholderMessages) { msg in
                MessageBubble(message: msg)
                    .id(msg.id)
            }
        }
        .padding(.horizontal, DS.Space._16)
        .padding(.top, DS.Space._16)
        .padding(.bottom, DS.Space._12)
    }
}
```

**Placeholder messages:** Private static array of 4-5 structs with `id`, `role` (user/assistant), `text`. Demonstrates both user (trailing, accent bg, tail bottom-right) and assistant (leading, white@5% bg, tail bottom-left) bubble styles.

**MessageBubble:** Private subview using `UnevenRoundedRectangle`:
- User: trailing align, max 80% width, corners 12/12/4/12, `chatBubbleUser` bg
- Assistant: leading align, max 80% width, corners 12/4/12/12, `chatBubbleAssistant` bg

**PlaceholderMessage struct:** Private, Identifiable. Fields: id (UUID), role (enum user/assistant), text (String).

---

### Step 7: Create ChatDetailView.swift

**Why:** Composes title bar + messages + composer. Per spec §5.3.

**File:** `macos/Sources/Features/Chat/Views/ChatDetailView.swift`

**Structure:**
```
VStack(spacing: 0) {
    ChatTitleBarZone(onOpenEditor: { /* no-op stub */ })
    Divider()
    ChatMessagesZone()
    Divider()
    ChatComposerZone()
}
.background(Color(nsColor: theme.secondaryBackground))
```

---

### Step 8: Create ChatWindowRootView.swift (the real one)

**Why:** Top-level view replacing inline placeholder. Per spec §5.1.

**File:** `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`

**Structure:**
```
struct ChatWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView {
            ChatSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            ChatDetailView()
        }
        .background(Color(nsColor: theme.background))
    }
}
```

---

### Step 9: Update SmithersApp.swift — remove inline placeholders

**Why:** Replace inline ChatWindowRootView with import from Features/Chat/Views/.

**Changes:**
- Remove lines 39-49 (inline `ChatWindowRootView` struct)
- Keep `IDEWindowRootView` inline placeholder for now (IDE ticket handles that)

The new `ChatWindowRootView` in Features/Chat/Views/ will be found by the compiler since it's in the same target.

**Modify:** `macos/Sources/App/SmithersApp.swift`

---

### Step 10: Add all new files to Xcode project

**Why:** The 7 new Chat view files must be registered in .pbxproj.

**New files to register in app target:**
1. `Sources/Features/Chat/Views/ChatWindowRootView.swift`
2. `Sources/Features/Chat/Views/ChatSidebarView.swift`
3. `Sources/Features/Chat/Views/SidebarModeBar.swift`
4. `Sources/Features/Chat/Views/ChatDetailView.swift`
5. `Sources/Features/Chat/Views/ChatMessagesZone.swift`
6. `Sources/Features/Chat/Views/ChatComposerZone.swift`
7. `Sources/Features/Chat/Views/ChatTitleBarZone.swift`

**Create groups in PBXGroup:**
- Features group → Chat group → Views group

**Modify:** `macos/Smithers.xcodeproj/project.pbxproj`

**Note:** Steps 0 and 10 can be combined into a single pbxproj edit, but logically they're separate concerns (fixing existing vs adding new). In practice, do one comprehensive pbxproj edit.

---

### Step 11: Write ChatWindowTests.swift

**Why:** TDD — validate the chat window shell compiles and has expected structure.

**File:** `macos/SmithersTests/ChatWindowTests.swift`

**Tests:**
1. `sidebarModeEnumHasThreeCases` — SidebarMode.allCases.count == 3
2. `sidebarModeIcons` — verify each mode returns correct SF Symbol name
3. `sidebarModeLabels` — verify display labels
4. `placeholderMessagesExist` — ChatMessagesZone has placeholder data (if exposed)
5. `appModelHasWorkspaceName` — AppModel().workspaceName == "Smithers"

**Register in test target** in .pbxproj.

---

### Step 12: Verify green build

Run full verification:
1. `zig build all` — Zig checks pass (no Zig changes, but verify nothing broke)
2. `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers -configuration Debug` — Swift compiles clean, zero warnings
3. `xcodebuild test -project macos/Smithers.xcodeproj -scheme SmithersTests -configuration Debug` — all tests pass (if test target setup works)

If xcodebuild test fails due to test target configuration issues (TEST_HOST/BUNDLE_LOADER), document in triage and note — the core build must pass.

---

## File Inventory

### Files to Create (7 + 1 test)

| File | Purpose |
|------|---------|
| `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` | NavigationSplitView root |
| `macos/Sources/Features/Chat/Views/ChatSidebarView.swift` | Sidebar: mode bar + stub content |
| `macos/Sources/Features/Chat/Views/SidebarModeBar.swift` | Chats/Source/Agents toggle |
| `macos/Sources/Features/Chat/Views/ChatDetailView.swift` | Title + Messages + Composer |
| `macos/Sources/Features/Chat/Views/ChatMessagesZone.swift` | ScrollView + LazyVStack + placeholder bubbles |
| `macos/Sources/Features/Chat/Views/ChatComposerZone.swift` | TextField + Send button |
| `macos/Sources/Features/Chat/Views/ChatTitleBarZone.swift` | 28pt title bar + Open Editor |
| `macos/SmithersTests/ChatWindowTests.swift` | Unit tests for chat shell |

### Files to Modify (3)

| File | Change |
|------|--------|
| `macos/Smithers.xcodeproj/project.pbxproj` | Add ALL existing + new files, fix test target config |
| `macos/Sources/App/SmithersApp.swift` | Remove inline ChatWindowRootView placeholder |
| `macos/Sources/App/AppModel.swift` | Add `workspaceName` property |

---

## Risks

1. **Xcode project file corruption** — Hand-editing .pbxproj is error-prone. UUID collisions or missing entries cause cryptic build failures. Mitigation: follow existing UUID convention (readable hex), verify build after each batch of additions.

2. **Test target configuration** — SmithersTests may need TEST_HOST/BUNDLE_LOADER to `@testable import Smithers`. If this can't be resolved without restructuring, document and skip test execution (keep tests compiling).

3. **NavigationSplitView sidebar behavior** — macOS NavigationSplitView can have unexpected default column widths and collapse behavior. Mitigation: explicit `.navigationSplitViewColumnWidth(min:ideal:max:)` per spec.

4. **Swift 6 strict concurrency warnings** — Any closure crossing actor boundaries needs careful handling. Mitigation: all models `@MainActor`, views are implicitly main actor, closures in Button actions are fine.

5. **`zig build all` doesn't run xcodebuild** — Acceptance criteria says "zig build xcode-test passes" but this step may not be wired in build.zig. If not wired, run xcodebuild directly and document the gap.

---

## Dependency Graph

```
Step 0: Fix pbxproj (existing files)
  ↓
Step 1: AppModel.workspaceName
  ↓
Steps 2-6: Leaf views (parallel — no deps between them)
  ├── Step 2: SidebarModeBar
  ├── Step 4: ChatTitleBarZone
  ├── Step 5: ChatComposerZone
  └── Step 6: ChatMessagesZone
  ↓
Step 3: ChatSidebarView (depends on Step 2)
Step 7: ChatDetailView (depends on Steps 4, 5, 6)
  ↓
Step 8: ChatWindowRootView (depends on Steps 3, 7)
  ↓
Step 9: SmithersApp.swift update (depends on Step 8)
  ↓
Step 10: Add new files to pbxproj
  ↓
Step 11: Tests
  ↓
Step 12: Verify green
```

In practice, Steps 0+10 are one pbxproj edit (add everything at once), and Steps 2-8 are written in sequence but logically independent leaf→composite ordering.
