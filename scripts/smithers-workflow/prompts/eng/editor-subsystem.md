# Editor Subsystem

## 8.1 CodeEditorView (NSViewRepresentable)

`NSViewRepresentable` wrapping `MultiCursorTextView` (subclass of `STTextView`). Most complex view in app.

**Inputs (bindings/params):**
- `text: Binding<String>`, `language: SupportedLanguage?`, `theme: AppTheme`, `font: NSFont`, `lineSpacing: CGFloat`, `characterSpacing: CGFloat`, `ligaturesEnabled: Bool`, `cursorStyle: CursorStyle`, `showLineNumbers: Bool`, `highlightCurrentLine: Bool`, `showIndentGuides: Bool`, `showMinimap: Bool`, `scrollbarMode: ScrollbarVisibilityMode`, `scrollToRequest: ScrollToRequest?` (line/col, set by showInEditor), `ghostText: String?` (AI completion), `onTextChange: (String) -> Void`, `onCursorChange: (Int, Int) -> Void`

**makeNSView:** Creates STTextView via `MultiCursorTextView.scrollableTextView()`, extracts text view + scroll view, creates line number ruler (`STLineNumberRulerView`), custom `ScrollbarOverlayView`, `GhostTextOverlayView`, wraps in `ScrollbarHostingView`.

**Coordinator:** Weak refs to subviews. Caches highlighters per language. `STTextViewDelegate` for text change notifications. Manages highlight → apply cycle. Tracks file URL changes → save/restore view state (scroll, selection).

**updateNSView:** Handles theme changes (reapply colors), font changes (reload with new attrs), text changes from outside (AI wrote file), scroll requests (animate to line/col).

## 8.2 TreeSitter Highlighting Pipeline

```
User types → onTextChange callback
→ EditorStateModel updates activeFileContent
→ CodeEditorView.updateNSView detects change
→ Coordinator.scheduleHighlight()
→ 250ms debounce (cancels previous)
→ Increment requestID
→ Dispatch to parseQueue (background, .userInitiated QoS)
→ Parse with TreeSitter
→ Run highlight query, collect captures
→ Map captures to colors via syntax palette
→ Check requestID still matches (not stale)
→ Dispatch to main thread
→ Apply attrs to NSTextStorage via setAttributes(_:range:)
```

**Cancellation:** Increment `requestID`. Before apply, check `currentID == self.requestID`. Stale discarded.

**Size limit:** Skip highlighting if > 200,000 chars. Plain foreground only.

**Language registry:** `SupportedLanguages.swift` maps extensions to TreeSitter `Language`:

| Ext | Language |
|-----|----------|
| `.swift` | TreeSitterSwift |
| `.js` | TreeSitterJavaScript |
| `.ts` | TreeSitterTypeScript |
| `.tsx` | TreeSitterTypeScript (TSX) |
| `.py` | TreeSitterPython |
| `.json` | TreeSitterJSON |
| `.sh`, `.bash`, `.zsh` | TreeSitterBash |
| `.md`, `.markdown` | TreeSitterMarkdown (block + inline) |
| `.zig` | TreeSitterZig |
| `.rs` | TreeSitterRust |
| `.go` | TreeSitterGo |

## 8.3 Multi-Cursor Support

`MultiCursorTextView` subclasses `STTextView`. Overrides `mouseDown`, `keyDown`, `insertText`, delete, `doCommand`.

- **Option+Click:** Add insertion at click
- **Option+Shift+Up/Down:** Add cursor on adjacent line
- **Cmd+D:** Select next occurrence
- **Cmd+Shift+L:** Select all occurrences
- **Escape:** Collapse to single cursor

All edits grouped into single undo via `groupedUndoIfNeeded`.

Copy/paste with multi-cursor: one pasteboard item per selection. Paste distributes across cursors.

## 8.4 Ghost Text (AI Completions)

`GhostTextOverlayView` = `NSView` subclass over editor. Renders dimmed preview at cursor using `NSTextStorage` + `NSLayoutManager` + `NSTextContainer`.

- Visibility: fade in/out with `NSAnimationContext` (0.12s)
- Hit testing: always nil (pass-through)
- Tab accepts (inserts into editor)
- Escape dismisses
- Typing advances through suggestion or cancels if diverges

Pipeline: `CompletionService` sends requests to codex-app-server after 300ms debounce. Streaming partial results update ghost text real-time. Each keystroke cancels previous, starts new.

## 8.5 Scrollbar Overlay

`ScrollbarOverlayView` — custom `NSView`, manual drawing. Replaces native macOS scrollbar.

- Modes: always (visible), automatic (shows on scroll, fades after 1.5s), never (hidden)
- Knob sizing: proportional to viewport/content ratio, min 24pt
- Interaction: click track for page scroll, drag knob for continuous
- Drawing: filled rounded rect (4pt radius), alpha varies (0.38 idle, 0.55 hover/drag)
- Hit testing: nil when invisible (alpha < 0.01)

## 8.6 Bracket Matching

`BracketMatcher` scans outward from cursor for matching pairs: `()`, `[]`, `{}`, `<>`. Scans up to 10,000 chars each direction. Matching bracket highlighted with `white@16%` bg.

## 8.7 Neovim Mode

Toggled via Cmd+Shift+N. When enabled, `CodeEditorView` replaced by `GhosttyTerminalView` running embedded Neovim.

**NvimController** (in SmithersApp, not SmithersEditor):

1. Creates Unix socket `/tmp/smithers-nvim-<uuid>.sock`
2. Launches Neovim in hidden Ghostty terminal with `--listen <socket>`
3. Connects with retry (10 attempts, 100ms backoff)
4. Attaches UI with ext_multigrid, ext_cmdline, ext_popupmenu, ext_messages, ext_hlstate
5. Installs autocmds for BufEnter/BufLeave → track file changes
6. Starts notification loop for Neovim events

**Bidirectional sync:**
- User selects file in sidebar → NvimController sends `:edit <path>` via RPC
- User opens in Neovim → BufEnter autocmd → NvimController updates `TabModel` + `EditorStateModel`
- User saves in Neovim → BufWritePost → NvimController marks clean

**External UI overlays** (`NvimExtUIOverlay`):
- Cmdline: SwiftUI overlay at bottom
- Popup menu: SwiftUI list at cursor
- Messages: floating notifications (max 6, auto-expire 4s)
- Floating windows: plugin popups with blur, rounded corners, shadow

**Theme derivation:** On UI attach, NvimController reads highlight groups (Normal, Visual, CursorLine, TabLine, etc.), derives `AppTheme` via `ThemeDerived.fromNvimHighlights()`. Overrides default theme while Neovim active.

**Crash recovery:** If Neovim dies → recovery view: Restart Neovim, Disable Neovim Mode, Reveal Crash Report.
