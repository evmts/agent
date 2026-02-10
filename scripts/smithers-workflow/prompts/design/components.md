# Design Components — Shared Components Library & View Hierarchy

## 3) Shared components library

These components are used in both windows. Keep them in a `DesignSystem` module (or folder) with tokens and reusable views.

### 3.1 `IconButton`

- Sizes:

  - Small: 24×24 (toolbar-ish)
  - Medium: 28×28
  - Large: 32×32 (primary actions like send)

- Style:

  - Default: no background
  - Hover: `white@6%` background
  - Active/pressed: `white@10%` background

- Icon size: 14–16pt
- Optional tooltip via `.help()`

### 3.2 `PrimaryButton`

Used for "New Chat", "Open Folder…", etc.

- Height: 32pt
- Padding: 12pt horizontal
- Corner radius: 8
- Background: `accent @ 90%` (or solid accent)
- Text: white 92%
- Hover: brighten by +6% (or overlay white @ 6%)
- Disabled: opacity 45%, cursor not allowed

### 3.3 `PillButton`

Category pills on chat landing:

- Corner radius: 999
- Padding: 14pt h / 8pt v
- Background: `chat.pill.bg`
- Border: 1px `chat.pill.border`
- Hover/active: background `chat.pill.active`

### 3.4 `Panel`

For overlays and cards:

- Background: `surface2` for chrome-like, `surface1` for content-like
- Border: 1px `color.border`
- Corner radius: 10–16 depending on size

### 3.5 `SidebarListRow`

- Height: 44pt default, can compress to 36pt in dense mode
- Hover: `white@4%`
- Selected: `accent@12%` fill
- Text:

  - Title: `type.chatSidebarTitle` 12pt, primary
  - Secondary: 10pt, tertiary

### 3.6 `Badge`

Exit codes, applied/failed tags, etc.

- Height: 18–20pt
- Padding: 6pt h / 2pt v
- Corner radius: 6
- Background: semantic @ 18%
- Text: semantic @ 95% (or white 88% for contrast)

---

## 4) Complete view hierarchy

### 4.1 App root / scenes

**App-level structure (conceptual SwiftUI hierarchy):**

- `SmithersApp`

  - `AppModel` (shared) as `@StateObject`
  - Scene: `ChatWindowScene`

    - Root: `ChatWindowRootView`

  - Scene: `IDEWindowScene` (hidden until opened)

    - Root: `IDEWindowRootView`

  - Scene: `SettingsScene`

    - Root: `SettingsRootView` (standard macOS Settings window)
