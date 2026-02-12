# Research Context: editor-sttextview-scaffold

## Ticket Summary
Create `CodeEditorView` (NSViewRepresentable wrapping NSTextView) under `macos/Sources/Editor/` with theme hooks. No TreeSitter, no multi-cursor. Placeholder for future STTextView migration.

## Key Findings

### 1. Existing NSViewRepresentable Pattern (v2 codebase)

The v2 codebase already has ONE NSViewRepresentable: `KeyHandlingTextView` in `ChatComposerZone.swift` (line 5). This is the closest in-repo pattern to follow:

```swift
// macos/Sources/Features/Chat/Views/ChatComposerZone.swift
private struct KeyHandlingTextView: NSViewRepresentable {
    @Binding var text: String
    let onSend: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeyHandlingTextView
        init(_ parent: KeyHandlingTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView { parent.text = tv.string }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView { ... }
    func updateNSView(_ scroll: NSScrollView, context: Context) { ... }
}
```

### 2. V1 CodeEditor Pattern (reference, don't copy)

V1 `ContentView.swift` at `prototype0/Smithers/ContentView.swift` line 23 has the full `CodeEditor: NSViewRepresentable`. Key differences from what we need:
- Uses `STTextView` (via SPM dependency `krzyzanowskim/STTextView` v0.9.0)
- Has ~30 parameters (bindings for selection, scroll, font size, language, etc.)
- Complex Coordinator (line 449) with tree-sitter, ghost text, scrollbar overlay, cursor overlays
- **We need a MINIMAL version** — just NSTextView + theme colors + font

V1 Coordinator key init pattern:
```swift
@MainActor class Coordinator: NSObject, @preconcurrency STTextViewDelegate {
    var parent: CodeEditor
    init(parent: CodeEditor) { self.parent = parent }
}
```

V1 makeNSView key setup (simplified for our scaffold):
```swift
func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()  // or STTextView equivalent
    let textView = scrollView.documentView as! NSTextView
    textView.font = font
    textView.backgroundColor = theme.background
    textView.textColor = theme.foreground
    textView.delegate = context.coordinator
    return scrollView
}
```

### 3. AppTheme — Already Has Editor Tokens

`macos/Sources/Helpers/DesignSystem/AppTheme.swift` already defines editor-relevant properties:
- `background` (NSColor) — editor bg
- `foreground` (NSColor) — text color
- `selectionBackground` — selection highlight
- `lineHighlight` — current line bg
- `lineNumberForeground` / `lineNumberSelectedForeground` — line number colors
- `matchingBracket` — bracket highlight

Access pattern: `@Environment(\.theme) private var theme` then use `theme.background`, etc.

### 4. Design Tokens — Typography

`macos/Sources/Helpers/DesignSystem/Tokens.swift`:
- `DS.Typography.base = 13` — default body/code font size (spec §2.5)
- `DS.Typography.lineHeightCode = 1.4` — code line height multiplier
- System monospace font: `.monospacedSystemFont(ofSize: DS.Typography.base, weight: .regular)`

### 5. Test Pattern

The project uses TWO test frameworks:
- **Swift Testing** (`@Suite`, `@Test`, `#expect`) — used in `DesignSystemTests.swift`, `FileTreeSidebarTests.swift` (newer tests)
- **XCTest** (`XCTestCase`, `XCTAssert*`) — used in `ComponentsTests.swift`

Ticket says "compile-time test" — follow the Swift Testing pattern (consistent with newer tests):

```swift
// macos/SmithersTests/FileTreeSidebarTests.swift — reference pattern
import Testing
import AppKit
@testable import Smithers

@Suite @MainActor struct FileTreeSidebarTests {
    @Test func instantiateSidebar_viewTypeExists() {
        let view = FileTreeSidebar()
        #expect(String(describing: type(of: view)) == "FileTreeSidebar")
    }
    @Test func typography_isElevenPoints_perDesignToken() {
        #expect(FileTreeRow.rowFontSize == DS.Typography.s)
    }
}
```

### 6. Xcode Project Structure

The pbxproj at `macos/Smithers.xcodeproj/project.pbxproj` must be manually updated to add new files. Current structure:

```
Sources (A00000000000000000000004)
├── App/
├── Ghostty/
├── Helpers/ (Extensions/, DesignSystem/)
├── Services/
└── Features/
    ├── Chat/ (Views/, Models/)
    └── IDE/ (Views/, Sidebar/)
```

To add `Editor/` we need:
1. New PBXGroup for `Editor` under `Sources`
2. PBXFileReference entries for each .swift file
3. PBXBuildFile entries in both app Sources phase AND test Sources phase (for shared files)
4. Add the group to the Sources children list

**Editor files should go under `macos/Sources/Editor/`** (per spec — Editor is a subsystem, not a Feature).

### 7. File Locations to Create

Per spec and folder structure:
```
macos/Sources/Editor/
├── CodeEditorView.swift          — NSViewRepresentable
└── CodeEditorCoordinator.swift   — Coordinator (or nested inside CodeEditorView)
```

Test file:
```
macos/SmithersTests/CodeEditorViewTests.swift
```

### 8. No STTextView Dependency Yet

STTextView is NOT added to the v2 Xcode project's SPM dependencies. The ticket says "placeholder for STTextView" — use plain `NSTextView` for now. When STTextView is added later, swap the NSTextView subclass.

## Gotchas / Pitfalls

1. **Swift 6 strict concurrency** — Project uses `SWIFT_STRICT_CONCURRENCY = complete`. The Coordinator must be `@MainActor` or handle `Sendable` carefully. V1 uses `@MainActor class Coordinator: NSObject, @preconcurrency STTextViewDelegate`.

2. **NSTextView.scrollableTextView()** — This static method returns an NSScrollView with the NSTextView already configured as its documentView. This is the standard AppKit pattern. The makeNSView return type should be `NSScrollView` (not NSTextView).

3. **pbxproj editing** — IDs must be unique 24-character hex strings. Follow the existing ID patterns (e.g., `ED` prefix for Editor). Files must be added to BOTH the app's Sources build phase AND test target if needed by tests.

4. **Coordinator parent reference** — Use `var parent: CodeEditorView` (mutable, not let) because `updateNSView` updates `coord.parent = self` to keep the coordinator's reference fresh.

5. **Font construction** — Use `NSFont.monospacedSystemFont(ofSize:weight:)` for the code font, not `.systemFont(ofSize:)`. The spec says "System monospace / SF Mono" at 13pt default.

## Implementation Approach

Minimal scaffold:
- `CodeEditorView: NSViewRepresentable` with params: `text: Binding<String>`, `theme: AppTheme`, `font: NSFont` (defaulted)
- `Coordinator: NSObject, NSTextViewDelegate` with `textDidChange` syncing text back
- `makeNSView` creates `NSTextView.scrollableTextView()`, sets bg/fg/font from theme+tokens
- `updateNSView` handles theme changes and external text changes
- Expose `static let defaultFont` and `static let defaultFontSize` for tests to verify
- Test: construct view, verify font size matches `DS.Typography.base`, verify type name exists

## Reference Code Snippets

### NSTextView.scrollableTextView() setup (clean room, no STTextView)
```swift
func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    guard let textView = scrollView.documentView as? NSTextView else {
        return scrollView
    }
    textView.font = font
    textView.backgroundColor = theme.background
    textView.textColor = theme.foreground
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.delegate = context.coordinator
    textView.string = text
    scrollView.backgroundColor = theme.background
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    return scrollView
}
```
