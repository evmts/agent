# Design Spec: Settings / Preferences Window (Section 9)

## 9) Settings / Preferences window

Use standard macOS Settings window pattern with a sidebar list of categories.

### Categories

- Appearance

  - Theme: Dark / Light / System
  - Window transparency toggle + opacity slider (70–100%)

- Editor

  - Font name, size (8–48)
  - Ligatures
  - Line spacing, character spacing
  - Cursor shape (bar/block/underline)

- Display

  - Line numbers, current line highlight, indent guides, minimap, scrollbar mode

- Terminal

  - Option-as-Meta: left/right/both/none

- Neovim

  - Binary path
  - Floating window blur/radius/shadow

- Behavior

  - Close warnings
  - Auto-save toggle + interval
  - **Auto-open IDE on AI file change** (new; default on)

- Updates

  - Stable / Snapshot channel picker (if you have channels)
  - "Check for Updates..." button
  - Auto-check on launch toggle

### Sparkle auto-update system

Smithers uses **Sparkle** (`SPUStandardUpdaterController`) for automatic updates.

- **Update channels:** Release (stable) vs. Snapshot (pre-release/nightly). Persisted to UserDefaults. Changing channels switches the appcast feed URL.
- **Manual check:** "Check for Updates..." available in the menu bar icon menu and Preferences.
- **Auto-check:** On app launch (configurable, default on). Shows a non-intrusive notification when an update is available.
- **Feed URL:** Configured per-channel in Info.plist. Snapshot channel may include pre-release builds with experimental features.
- **Update flow:** Standard Sparkle dialog — shows release notes, "Install Update" / "Remind Me Later" / "Skip This Version".
