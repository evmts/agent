# Design System Tokens

## 2) Design system

You already provided the core tokens. Below is the normalized token table plus the missing semantic/system tokens needed to implement all states.

### 2.1 Color tokens (Dark default)

#### Surfaces

| Token            | Purpose                             | Value        |
| ---------------- | ----------------------------------- | ------------ |
| `color.base`     | Deepest background                  | `#0F111A`    |
| `color.surface1` | Primary panes                       | `#141826`    |
| `color.surface2` | Chrome (tab/status/sidebar headers) | `#1A2030`    |
| `color.border`   | 1px separators                      | `white @ 8%` |

#### Chat-specific surfaces

| Token                   | Purpose                 | Value          |
| ----------------------- | ----------------------- | -------------- |
| `chat.sidebar.bg`       | Chat sidebar background | `#0C0E16`      |
| `chat.sidebar.hover`    | Row hover               | `white @ 4%`   |
| `chat.sidebar.selected` | Selected session        | `accent @ 12%` |
| `chat.pill.bg`          | Category pill bg        | `white @ 6%`   |
| `chat.pill.border`      | Category pill border    | `white @ 10%`  |
| `chat.pill.active`      | Pill hover/active       | `accent @ 15%` |
| `titlebar.bg`           | Titlebar background     | `#141826`      |
| `titlebar.fg`           | Titlebar text           | `white @ 70%`  |

#### Chat bubbles

| Token                   | Purpose             | Value          |
| ----------------------- | ------------------- | -------------- |
| `chat.bubble.assistant` | Assistant bubble    | `white @ 5%`   |
| `chat.bubble.user`      | User bubble         | `accent @ 12%` |
| `chat.bubble.command`   | Command bubble      | `white @ 4%`   |
| `chat.bubble.status`    | Status bubble       | `white @ 4%`   |
| `chat.bubble.diff`      | Diff preview bubble | `white @ 5%`   |
| `chat.input.bg`         | Input field bg      | `white @ 6%`   |

#### Accent & semantic

| Token           | Purpose                       | Value                                                            |
| --------------- | ----------------------------- | ---------------------------------------------------------------- |
| `color.accent`  | Primary accent                | `#4C8DFF`                                                        |
| `color.success` | Success (exit 0, applied)     | `#34D399` (or system green variant; keep saturated but not neon) |
| `color.warning` | Warning (declined, conflicts) | `#FBBF24`                                                        |
| `color.danger`  | Error (exit !=0, failed)      | `#F87171`                                                        |
| `color.info`    | Informational status          | `#60A5FA`                                                        |

> Note: use semantic colors **sparingly**; most UI remains neutral. Semantic appears as small badges/indicators, not full-pane fills.

### 2.2 Text opacity hierarchy

| Level     | Token            | Opacity | Usage                  |
| --------- | ---------------- | ------: | ---------------------- |
| Primary   | `text.primary`   |     88% | main text              |
| Secondary | `text.secondary` |     60% | descriptions, inactive |
| Tertiary  | `text.tertiary`  |     45% | timestamps, hints      |

### 2.3 Syntax palette (Nova-inspired)

| Token type        | Color            |
| ----------------- | ---------------- |
| Keywords          | `#FF5370`        |
| Strings           | `#C3E88D`        |
| Functions         | `#82AAFF`        |
| Comments          | `#676E95`        |
| Types             | `#FFCB6B`        |
| Variables/Props   | `#F07178`        |
| Numbers/Constants | `#D4C26A`        |
| Operators         | `#89DDFF`        |
| Punctuation       | `gray @ 70%`     |
| Tags (JSX/HTML)   | coral/red family |

### 2.4 Light theme derivation (required)

Implement a deterministic derivation so engineering isn't hand-tuning 30 colors.

**Algorithm (recommended):**

- Keep `accent` identical.
- Replace surface stack with near-white neutrals:

  - `base` → `#F6F7FB`
  - `surface1` → `#FFFFFF`
  - `surface2` → `#EEF1F7`
  - `border` → `black @ 10%`

- Text opacities map to black at same opacities (primary 88%, etc.)
- Chat bubbles:

  - assistant → `black @ 4%`
  - user → `accent @ 12%` (unchanged tint logic)

- Hover states use `black @ 3–4%` instead of white.

### 2.5 Typography

Use system fonts; no custom font files.

#### UI font

- System UI: `.system` (SF Pro)
- Weights:

  - Regular for body
  - Medium for labels
  - Semibold for headings

#### Code font

- System monospace: `.monospaced` / SF Mono
- Default size: 13pt (code), 14pt if you want closer to current Smithers feel.

#### Scale (from your prompt)

| Token                   | Size | Usage                                 |
| ----------------------- | ---: | ------------------------------------- |
| `type.xs`               |   10 | timestamps, tiny labels, line numbers |
| `type.s`                |   11 | sidebar items, status bar             |
| `type.base`             |   13 | default body, chat, code              |
| `type.l`                |   15 | section headers                       |
| `type.xl`               |   20 | dialogs, empty state headings         |
| `type.chatHeading`      |   28 | "How can I help you?"                 |
| `type.chatSubheading`   |   16 | project name under heading            |
| `type.chatSidebarTitle` |   12 | session title                         |
| `type.chatTimestamp`    |   10 | session timestamp                     |

Line height multipliers:

- UI text: **1.35**
- Chat messages: **1.5**
- Code: **1.4**

### 2.6 Spacing & sizing

4pt grid. Primary component metrics:

- `space.4 = 4`
- `space.6 = 6`
- `space.8 = 8`
- `space.10 = 10`
- `space.12 = 12`
- `space.16 = 16`
- `space.24 = 24`
- `space.32 = 32`

Common heights:

- Sidebar mode bar: **40pt**
- Title bar zone: **28pt**
- Status bar: **22pt**
- Tab bar: **32pt**
- Input send button: **32×32**

### 2.7 Corner radii

| Token       | Value | Usage                |
| ----------- | ----: | -------------------- |
| `radius.4`  |     4 | chat tail corner     |
| `radius.6`  |     6 | buttons, small cards |
| `radius.8`  |     8 | pills, inputs, tabs  |
| `radius.10` |    10 | input bar container  |
| `radius.12` |    12 | chat bubbles         |
| `radius.16` |    16 | dialogs, large cards |

### 2.8 Borders & separators

- 1px separators use `color.border` (white 8% / black 10% in light)
- Avoid heavy strokes; use separators between structural panes only.

### 2.9 Shadows

Only on overlays (command palette, image viewer, modals):

- Shadow: y=10, blur=30, color black @ 35% (dark) / black @ 18% (light)
