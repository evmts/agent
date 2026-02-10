# Spec Index & Ownership

Every topic has ONE canonical doc. Dependent docs may reference but MUST NOT redefine.

## Topic Ownership

| Topic | Canonical Doc | Dependent Docs |
|-------|--------------|----------------|
| **Window architecture** | `design/principles.md` §1 | `eng/window-management.md` (impl details) |
| **Chat UI** | `design/chat-window.md` | `eng/chat-implementation.md` (impl details) |
| **IDE UI** | `design/ide-window.md` | `eng/ide-implementation.md` (impl details) |
| **Keyboard shortcuts** | `design/keyboard-shortcuts.md` | `eng/keyboard-input.md` (impl details) |
| **Design tokens** | `design/system-tokens.md` | `eng/design-system-impl.md` (impl details) |
| **Skills system** | `eng/skills-system.md` | `design/overlays.md` (UI only) |
| **AI integration** | `eng/ai-integration.md` | `design/chat-window.md` (UI only) |
| **Terminal** | `eng/terminal-subsystem.md` | `design/ide-window.md` (UI only) |
| **Editor** | `eng/editor-subsystem.md` | `design/ide-window.md` (UI only) |
| **JJ/VCS** | `eng/jj-integration.md` | `design/chat-window.md` (sidebar UI only) |
| **State architecture** | `eng/state-architecture.md` | — |
| **Build/repo** | `eng/repo-build.md` | `CLAUDE.md` (summary) |
| **Testing** | `eng/testing.md` | `always-green.md` (policy) |
| **Phases** | `eng/implementation-phases.md` | `mvp-scope.md` (gating) |
| **Web app** | `eng/web-app.md` | — |
| **Code style (Zig)** | `zig-rules.md` + `ghostty-patterns.md` | — |
| **Code style (Swift)** | `swift-rules.md` | — |
| **Font/typography** | `design/system-tokens.md` §2.5 | `swift-rules.md` (must reference, not redefine) |
| **Security posture** | `eng/security-posture.md` | `eng/web-app.md` (references) |
| **MVP scope** | `mvp-scope.md` | `eng/implementation-phases.md` (references) |
| **Conflict resolution** | `spec-precedence.md` | — |

## Rules

- **Canonical doc** defines the truth. Other docs may add implementation detail but must link back.
- If you find a contradiction between canonical and dependent docs, the canonical doc wins.
- When updating a topic, update the canonical doc first; dependent docs only if they add impl detail.
- New topics should be added to this index before writing specs.
