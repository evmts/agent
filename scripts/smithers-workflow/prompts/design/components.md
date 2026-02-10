# Shared Components & View Hierarchy

## 3) Components library

Used in both windows. Keep in `DesignSystem` module with tokens + reusable views.

### 3.1 `IconButton`

Sizes: Small 24×24 (toolbar), Medium 28×28, Large 32×32 (primary); Default: no bg, Hover `white@6%`, Active `white@10%`; Icon 14–16pt; Tooltip via `.help()`

### 3.2 `PrimaryButton`

32pt height, 12pt h padding, radius 8, `accent@90%` bg, white 92% text; Hover brighten +6% (or `white@6%` overlay); Disabled 45% opacity

### 3.3 `PillButton`

Radius 999, padding 14pt h / 8pt v, `chat.pill.bg`, border 1px `chat.pill.border`; Hover/active `chat.pill.active`

### 3.4 `Panel`

Bg `surface2` (chrome) or `surface1` (content), border 1px `color.border`, radius 10–16

### 3.5 `SidebarListRow`

44pt (or 36pt dense); Hover `white@4%`, selected `accent@12%`; Title `type.chatSidebarTitle` 12pt primary, secondary 10pt tertiary

### 3.6 `Badge`

18–20pt, padding 6pt h / 2pt v, radius 6, semantic@18% bg, semantic@95% text (or white 88% contrast)

---

## 4) View hierarchy

### 4.1 App root / scenes

- `SmithersApp`
  - `AppModel` (@State shared)
  - `ChatWindowScene` → `ChatWindowRootView`
  - `IDEWindowScene` (hidden until opened) → `IDEWindowRootView`
  - `SettingsScene` → `SettingsRootView` (standard macOS)
