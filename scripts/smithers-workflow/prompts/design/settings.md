# Settings / Preferences Window

## 9) Settings

Standard macOS Settings window with sidebar list of categories.

### Categories

**Appearance:** Theme Dark/Light/System; Window transparency toggle + opacity slider 70–100%

**Editor:** Font name, size 8–48; Ligatures; Line spacing, char spacing; Cursor shape bar/block/underline

**Display:** Line numbers, current line highlight, indent guides, minimap, scrollbar mode

**Terminal:** Option-as-Meta left/right/both/none

**Neovim:** Binary path; Floating window blur/radius/shadow

**Behavior:** Close warnings; Auto-save toggle + interval; Auto-open IDE on AI file change (new, default on)

**Updates:** Stable/Snapshot channel picker (if channels); "Check for Updates..." button; Auto-check on launch toggle

### Sparkle auto-update

Uses **Sparkle** (`SPUStandardUpdaterController`) for auto-updates.

- **Update channels:** Release (stable) vs. Snapshot (pre-release/nightly). Persisted UserDefaults. Changing channels switches appcast feed URL.
- **Manual check:** "Check for Updates..." in menu bar icon menu + Preferences.
- **Auto-check:** on app launch (configurable, default on). Non-intrusive notification when update available.
- **Feed URL:** configured per-channel Info.plist. Snapshot may include pre-release builds experimental features.
- **Update flow:** standard Sparkle dialog — shows release notes, "Install Update" / "Remind Me Later" / "Skip This Version".
