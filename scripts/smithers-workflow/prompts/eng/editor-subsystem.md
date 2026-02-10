# Editor Subsystem

## 8. Editor Subsystem

### 8.1 CodeEditorView (NSViewRepresentable)

The editor is an `NSViewRepresentable` wrapping `MultiCursorTextView` (a subclass of `STTextView`). This is the most complex view in the app.

**Inputs (bindings/parameters):**
- `text: Binding<String>` — bidirectional text content
- `language: SupportedLanguage?` — for syntax highlighting
- `theme: AppTheme` — colors
- `font: NSFont` — resolved from preferences
- `lineSpacing: CGFloat`
- `characterSpacing: CGFloat`
- `ligaturesEnabled: Bool`
- `cursorStyle: CursorStyle`
- `showLineNumbers: Bool`
- `highlightCurrentLine: Bool`
- `showIndentGuides: Bool`
- `showMinimap: Bool`
- `scrollbarMode: ScrollbarVisibilityMode`
- `scrollToRequest: ScrollToRequest?` — line/column to scroll to (set by showInEditor)
- `ghostText: String?` — AI completion preview
- `onTextChange: (String) -> Void` — callback when user edits text
- `onCursorChange: (Int, Int) -> Void` — callback with (line, column)

**makeNSView:** Creates the STTextView via `MultiCursorTextView.scrollableTextView()`, extracts the text view and scroll view, creates the line number ruler (`STLineNumberRulerView`), creates the custom `ScrollbarOverlayView`, creates the `GhostTextOverlayView`, wraps everything in a `ScrollbarHostingView` container.

**Coordinator:** Holds weak references to all subviews. Caches highlighters per language. Implements `STTextViewDelegate` for text change notifications. Manages the highlight → apply cycle. Tracks file URL changes to save/restore view state (scroll position and selection).

**updateNSView:** Handles theme changes (reapply colors to existing text), font changes (reload content with new attributes), text changes from outside (e.g., AI wrote to the file), and scroll requests (animate to line/column).

### 8.2 TreeSitter highlighting pipeline

```
User types → onTextChange callback fires
→ EditorStateModel updates activeFileContent
→ CodeEditorView.updateNSView detects text change
→ Coordinator.scheduleHighlight() called
→ 250ms debounce (cancels previous request)
→ Increment requestID
→ Dispatch to parseQueue (background, .userInitiated QoS)
→ Parse text with TreeSitter parser
→ Run highlight query, collect captures
→ Map captures to colors via syntax palette
→ Check requestID still matches (not stale)
→ Dispatch to main thread
→ Apply attributes to NSTextStorage via setAttributes(_:range:)
```

**Cancellation:** Incrementing `requestID`. Before applying results, check `currentID == self.requestID`. Stale results are discarded.

**Size limit:** Skip highlighting for files > 200,000 characters. Apply plain foreground color only.

**Language registry:** `SupportedLanguages.swift` maps file extensions to TreeSitter `Language` instances:

| Extension | Language |
|-----------|----------|
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

### 8.3 Multi-cursor support

`MultiCursorTextView` subclasses `STTextView`. Overrides `mouseDown`, `keyDown`, `insertText`, delete methods, and `doCommand`.

- **Option+Click:** Add insertion point at click location.
- **Option+Shift+Up/Down:** Add cursor on adjacent line.
- **Cmd+D:** Select next occurrence of current selection.
- **Cmd+Shift+L:** Select all occurrences.
- **Escape:** Collapse to single cursor.

All multi-cursor edits are grouped into a single undo action via `groupedUndoIfNeeded`.

Copy/paste with multiple cursors: creates one pasteboard item per selection. Paste distributes items across cursors.

### 8.4 Ghost text (AI completions)

`GhostTextOverlayView` is an `NSView` subclass positioned over the editor. It renders dimmed preview text at the cursor position using `NSTextStorage` + `NSLayoutManager` + `NSTextContainer` for layout.

- Visibility: fade in/out with `NSAnimationContext` (0.12s duration).
- Hit testing: always returns `nil` (pass-through to editor).
- Tab accepts the completion (inserts text into editor).
- Escape dismisses.
- Typing advances through the suggestion or cancels if it diverges.

The completion pipeline: `CompletionService` sends requests to codex-app-server after 300ms debounce. Streaming partial results update the ghost text in real time. Each keystroke cancels the previous request and starts a new one.

### 8.5 Scrollbar overlay

`ScrollbarOverlayView` — custom `NSView` with manual drawing. Replaces the native macOS scrollbar.

- Modes: always (always visible), automatic (shows on scroll, fades after 1.5s), never (hidden).
- Knob sizing: proportional to viewport/content ratio, minimum 24pt.
- Interaction: click track for page scroll, drag knob for continuous scroll.
- Drawing: filled rounded rect (4pt radius), alpha varies by state (0.38 idle, 0.55 hover/drag).
- Hit testing: returns nil when invisible (alpha < 0.01).

### 8.6 Bracket matching

`BracketMatcher` scans outward from cursor position to find matching bracket pairs: `()`, `[]`, `{}`, `<>`. Scans up to 10,000 characters in each direction. Matching bracket highlighted with `white@16%` background.

### 8.7 Neovim mode

Toggled via Cmd+Shift+N. When enabled, the `CodeEditorView` is replaced by a `GhosttyTerminalView` running an embedded Neovim instance.

**NvimController** (lives in SmithersApp, not SmithersEditor):

1. Creates a Unix domain socket in `/tmp/smithers-nvim-<uuid>.sock`.
2. Launches Neovim in a hidden Ghostty terminal with `--listen <socket>`.
3. Connects to the socket with retry (10 attempts, 100ms backoff).
4. Attaches UI with ext_multigrid, ext_cmdline, ext_popupmenu, ext_messages, ext_hlstate.
5. Installs autocmds for BufEnter/BufLeave to track file changes.
6. Starts a notification loop to handle Neovim events.

**Bidirectional sync:**
- User selects file in sidebar → NvimController sends `:edit <path>` via RPC.
- User opens file in Neovim → BufEnter autocmd fires → NvimController updates `TabModel` and `EditorStateModel`.
- User saves in Neovim → BufWritePost autocmd fires → NvimController marks file as clean.

**External UI overlays** (`NvimExtUIOverlay`):
- Command line: SwiftUI overlay at bottom of editor area.
- Popup menu: SwiftUI list overlay positioned at cursor.
- Messages: floating notifications (max 6 visible, auto-expire after 4s).
- Floating windows: plugin popups with blur, rounded corners, shadow.

**Theme derivation:** On UI attach, NvimController reads highlight groups (Normal, Visual, CursorLine, TabLine, etc.) and derives an `AppTheme` using `ThemeDerived.fromNvimHighlights()`. This overrides the default theme while Neovim mode is active.

**Crash recovery:** If the Neovim process dies unexpectedly, show a recovery view with: Restart Neovim, Disable Neovim Mode, Reveal Crash Report.
