# Plan: editor-sttextview-scaffold

## Summary
Scaffold `CodeEditorView` (`NSViewRepresentable` wrapping `NSTextView`) under `macos/Sources/Editor/` with AppTheme color hooks and DS.Typography font tokens. No TreeSitter, no multi-cursor, no STTextView — plain NSTextView placeholder that unblocks TabModel integration and future editor features.

## Architecture Decisions

- **Editor is a subsystem, not a Feature** — lives at `macos/Sources/Editor/` (same level as `App/`, `Ghostty/`, `Helpers/`), not under `Features/`.
- **Plain NSTextView** — STTextView is not yet added as an SPM dependency. Use `NSTextView.scrollableTextView()` as the host. When STTextView is added later, swap the underlying text view.
- **Follow KeyHandlingTextView pattern** — the existing `NSViewRepresentable` in `ChatComposerZone.swift` is the in-repo pattern to follow: nested Coordinator, `makeNSView` returns `NSScrollView`, mutable `parent` on Coordinator.
- **Theme via `@Environment(\.theme)`** — `AppTheme` already has all editor-relevant tokens: `background`, `foreground`, `selectionBackground`, `lineHighlight`, `lineNumberForeground`.
- **Monospaced system font** — `NSFont.monospacedSystemFont(ofSize: DS.Typography.base, weight: .regular)` per spec §2.5 (SF Mono, 13pt).
- **Coordinator is nested** — keep Coordinator inside `CodeEditorView` (single file, no separate `CodeEditorCoordinator.swift`). Matches KeyHandlingTextView pattern and keeps scope minimal. Extract later when complexity grows.
- **Swift 6 strict concurrency** — Coordinator needs `@MainActor` annotation. Use `@preconcurrency NSTextViewDelegate` if needed.
- **Expose static constants** — `defaultFontSize` and `defaultFont` as static properties for test verification (matches `FileTreeRow.rowFontSize` / `FileTreeRow.indentPerLevel` pattern).

## Pre-existing Issue (Escape Hatch)
The test Sources build phase (line 258) references `CTXB000000000000000001 /* ChatHistoryStoreXCTest.swift */` but there is no corresponding `PBXBuildFile` or `PBXFileReference` entry. This is a pre-existing issue — do NOT fix as part of this ticket (would expand scope). Document in `docs/triage/preexisting-failures.md` if it causes build issues.

## Steps

### Step 0: Write test file (TDD — tests first)
**File:** `macos/SmithersTests/CodeEditorViewTests.swift`

Create Swift Testing tests that define the contract before implementation:
- `instantiateEditor_viewTypeExists` — construct `CodeEditorView` with sample text binding, verify type name
- `defaultFontSize_matchesDesignToken` — verify `CodeEditorView.defaultFontSize == DS.Typography.base` (13pt)
- `defaultFont_isMonospaced` — verify `CodeEditorView.defaultFont` is `NSFont.monospacedSystemFont`
- `lineHeightMultiplier_matchesCodeToken` — verify `CodeEditorView.lineHeightMultiplier == DS.Typography.lineHeightCode` (1.4)

Pattern: `@Suite @MainActor struct CodeEditorViewTests { ... }` with `#expect(...)` assertions, matching `FileTreeSidebarTests.swift`.

### Step 1: Create CodeEditorView implementation
**File:** `macos/Sources/Editor/CodeEditorView.swift`

Implement `CodeEditorView: NSViewRepresentable`:
- **Properties:**
  - `@Binding var text: String` — two-way text binding
  - `@Environment(\.theme) private var theme` — theme colors
  - `var font: NSFont = CodeEditorView.defaultFont` — configurable, defaults to SF Mono 13pt
- **Static constants:**
  - `static let defaultFontSize: CGFloat = DS.Typography.base` (13pt)
  - `static let defaultFont: NSFont = .monospacedSystemFont(ofSize: DS.Typography.base, weight: .regular)`
  - `static let lineHeightMultiplier: CGFloat = DS.Typography.lineHeightCode` (1.4)
- **Coordinator** (nested `final class`, `NSObject`, `NSTextViewDelegate`):
  - `var parent: CodeEditorView` (mutable for `updateNSView` refresh)
  - `textDidChange(_:)` — sync text back to binding
- **makeNSView(context:) -> NSScrollView:**
  - `NSTextView.scrollableTextView()` — standard AppKit factory
  - Extract `NSTextView` from `scrollView.documentView`
  - Set font, background, foreground, selection colors from theme
  - `isRichText = false`, disable auto-quote/data-detection
  - Set delegate to coordinator
  - Set initial text
  - Configure scroll view (vertical scroller, background)
  - Set `textContainerInset` for padding
  - Set line height via `NSMutableParagraphStyle` with `lineHeightMultiple`
  - Add `.accessibilityIdentifier("code_editor")`
- **updateNSView(_:context:):**
  - Sync external text changes (guard `tv.string != text`)
  - Refresh theme colors (background, foreground, selection) on theme change
  - Refresh font if changed
  - Update `context.coordinator.parent = self`

### Step 2: Update Xcode project (pbxproj)
**File:** `macos/Smithers.xcodeproj/project.pbxproj`

Add entries for new files using consistent ID scheme (`ED` prefix for Editor):

**PBXFileReference:**
- `ED00000000000000000001` — `CodeEditorView.swift` (path under Sources/Editor/)
- `ED00000000000000000002` — `CodeEditorViewTests.swift` (path SmithersTests/)

**PBXBuildFile:**
- `ED00000000000000000003` — CodeEditorView.swift in app Sources build phase
- `ED00000000000000000004` — CodeEditorViewTests.swift in test Sources build phase

**PBXGroup:**
- `ED00000000000000000005` — `Editor` group containing `ED00000000000000000001`
- Add `ED00000000000000000005` to Sources group (`A00000000000000000000004`) children

**Tests group:**
- Add `ED00000000000000000002` to Tests group (`B1111111111111111111111B`) children

### Step 3: Create physical files on disk
- `mkdir -p macos/Sources/Editor/`
- Write `macos/Sources/Editor/CodeEditorView.swift`
- Write `macos/SmithersTests/CodeEditorViewTests.swift`

### Step 4: Verify green
- Run `zig build all` — must pass (Zig build, fmt, prettier, typos, shellcheck)
- Run `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers -destination 'platform=macOS'` — must compile
- Run `xcodebuild test -project macos/Smithers.xcodeproj -scheme SmithersTests -destination 'platform=macOS'` — all tests pass including new CodeEditorViewTests

## File Summary

### Files to Create
1. `macos/Sources/Editor/CodeEditorView.swift` — NSViewRepresentable + nested Coordinator
2. `macos/SmithersTests/CodeEditorViewTests.swift` — Swift Testing suite

### Files to Modify
1. `macos/Smithers.xcodeproj/project.pbxproj` — add PBXFileReference, PBXBuildFile, PBXGroup entries

## Implementation Notes

### NSTextView.scrollableTextView() Pattern
```swift
func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    guard let textView = scrollView.documentView as? NSTextView else {
        return scrollView
    }
    // configure textView...
    return scrollView
}
```
The `NSTextView.scrollableTextView()` static factory creates an `NSScrollView` with a properly configured `NSTextView` as its `documentView`. This is the standard AppKit pattern — the return type of `makeNSView` is `NSScrollView`, not `NSTextView`.

### Line Height via Paragraph Style
```swift
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.lineHeightMultiple = CodeEditorView.lineHeightMultiplier
textView.defaultParagraphStyle = paragraphStyle
```

### Theme Color Application
```swift
textView.backgroundColor = theme.background
textView.textColor = theme.foreground
textView.selectedTextAttributes = [
    .backgroundColor: theme.selectionBackground,
    .foregroundColor: theme.foreground,
]
scrollView.backgroundColor = theme.background
```

### Concurrency Safety (Swift 6)
The Coordinator must handle Swift 6 strict concurrency. The simplest approach for a minimal scaffold is inheriting `@MainActor` from the test/view context, since `NSViewRepresentable` lifecycle methods run on main thread.

## Risks
1. **pbxproj merge conflicts** — manual edits to pbxproj are fragile. Mitigate by keeping changes minimal and testing build immediately.
2. **Swift 6 concurrency warnings** — `NSTextViewDelegate` conformance may trigger warnings. Use `@preconcurrency` attribute if needed.
3. **NSTextView.scrollableTextView() crash** — the `documentView as? NSTextView` cast should never fail, but guarded defensively.
4. **Pre-existing pbxproj issue** — `CTXB000000000000000001` reference in test build phase has no backing entries. May cause "missing file" warnings. Not in scope to fix.
