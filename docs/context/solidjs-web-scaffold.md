# Research Context: solidjs-web-scaffold

## Summary

Scaffold `web/` as a SolidJS + Vite + Tailwind CSS PWA with design tokens from prototype1. The build system already has a `zig build web` step that checks for `web/` directory existence — creating the directory with a working `pnpm build` is all that's needed.

---

## 1. Build System Integration (CRITICAL — already wired)

**File:** `build.zig` line 132

```zig
const web_step = addOptionalShellStep(b, "web", "Build web app (if web/ exists)",
    "if [ -d web ]; then cd web && pnpm install && pnpm build; else echo 'skipping web: web/ not found'; fi");
```

**Key facts:**
- `zig build web` runs: `cd web && pnpm install && pnpm build`
- `zig build all` (line 160-173) does NOT include web — only Zig build/test/fmt/lint + C header check
- `zig build dev` (line 143-149) DOES include web
- The `pnpm build` script in `web/package.json` must succeed for `zig build web` to pass
- Output goes to `web/dist/` (Vite default)

**No changes to build.zig needed.** Just create `web/` with a valid `pnpm build`.

## 2. Design Tokens — Exact CSS Variables from Prototype

**Source:** `prototype1/app/globals.css` (lines 1-101)

The prototype defines all Smithers tokens as CSS custom properties in `:root`. These are the **canonical dark theme values** from `docs/design.md` §2.1:

```css
/* Core surfaces */
--sm-base: #0F111A;
--sm-surface1: #141826;
--sm-surface2: #1A2030;
--sm-border: rgba(255, 255, 255, 0.08);

/* Chat sidebar */
--sm-sidebar-bg: #0C0E16;
--sm-sidebar-hover: rgba(255, 255, 255, 0.04);
--sm-sidebar-selected: rgba(76, 141, 255, 0.12);

/* Pills/badges */
--sm-pill-bg: rgba(255, 255, 255, 0.06);
--sm-pill-border: rgba(255, 255, 255, 0.10);
--sm-pill-active: rgba(76, 141, 255, 0.15);

/* Title bar */
--sm-titlebar-bg: #141826;
--sm-titlebar-fg: rgba(255, 255, 255, 0.70);

/* Chat bubbles */
--sm-bubble-assistant: rgba(255, 255, 255, 0.05);
--sm-bubble-user: rgba(76, 141, 255, 0.12);
--sm-bubble-command: rgba(255, 255, 255, 0.04);
--sm-bubble-status: rgba(255, 255, 255, 0.04);
--sm-bubble-diff: rgba(255, 255, 255, 0.05);

/* Input */
--sm-input-bg: rgba(255, 255, 255, 0.06);

/* Semantic colors */
--sm-accent: #4C8DFF;
--sm-success: #34D399;
--sm-warning: #FBBF24;
--sm-danger: #F87171;
--sm-info: #60A5FA;

/* Text opacity levels */
--sm-text-primary: rgba(255, 255, 255, 0.88);
--sm-text-secondary: rgba(255, 255, 255, 0.60);
--sm-text-tertiary: rgba(255, 255, 255, 0.45);

/* Syntax highlighting (Nova-inspired) */
--syn-keyword: #FF5370;
--syn-string: #C3E88D;
--syn-function: #82AAFF;
--syn-comment: #676E95;
--syn-type: #FFCB6B;
--syn-variable: #F07178;
--syn-number: #D4C26A;
--syn-operator: #89DDFF;
--syn-punctuation: rgba(255, 255, 255, 0.70);
--syn-tag: #FF5370;
```

**Additional design spec tokens to add (from design.md §2.1 Token Math Contract):**
```css
--sm-accent-rgb: 76, 141, 255; /* For rgba(var(--sm-accent-rgb), X/100) usage */
```

**shadcn HSL tokens** from prototype (for shadcn-solid compatibility):
```css
--background: 225 29% 8%;
--foreground: 0 0% 88%;
--primary: 217 100% 65%;
--primary-foreground: 0 0% 100%;
--secondary: 224 24% 14%;
--secondary-foreground: 0 0% 88%;
--muted: 224 24% 14%;
--muted-foreground: 0 0% 60%;
--accent: 224 24% 14%;
--accent-foreground: 0 0% 88%;
--destructive: 0 84% 60%;
--destructive-foreground: 0 0% 98%;
--card: 224 29% 10%;
--card-foreground: 0 0% 88%;
--popover: 224 29% 10%;
--popover-foreground: 0 0% 88%;
--border: 224 24% 18%;
--input: 224 24% 18%;
--ring: 217 100% 65%;
--radius: 0.5rem;
```

## 3. Prototype Layout Reference

**File:** `prototype1/app/page.tsx`

Dual-window layout: Chat (45% width) + IDE (55% width, togglable). For the scaffold placeholder, a simplified version:
- Full-height flex container with `background: var(--sm-base)`
- Left: Chat placeholder with sidebar stub and message area
- Right: IDE placeholder with file tree stub and editor area
- Use `--sm-*` variables throughout to demonstrate tokens working

## 4. Technology Stack Decisions

### SolidJS + Vite (not SolidStart)
- Spec says: "SolidJS Vite PWA" — plain Vite, no SolidStart framework
- Scaffold: `pnpm create solid` with `ts-tailwindcss` template, OR manual Vite setup
- **Recommendation: manual setup** for control over exact deps

### Tailwind CSS Version
- **Use Tailwind v3** (not v4) — shadcn-solid is built for Tailwind v3
- shadcn-solid uses `tailwindcss-animate` plugin and `tailwind.config` based approach
- Tailwind v4 uses CSS-first config (`@import "tailwindcss"`) which is incompatible with shadcn-solid's `tailwind.config.cjs` pattern
- prototype1 uses Tailwind v3 (`"tailwindcss": "^3.4.17"`)

### shadcn-solid Setup
- **Don't install shadcn-solid components yet** — just set up the infrastructure (cn utility, CSS vars, tailwind config)
- Components added incrementally via `npx shadcn-solid@latest add <component>`
- Uses `@kobalte/core` (Radix equivalent for Solid) and `class-variance-authority`

### Key Dependencies for Scaffold
```json
{
  "dependencies": {
    "solid-js": "^1.9",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "tailwind-merge": "^2.5.5"
  },
  "devDependencies": {
    "vite": "^6",
    "vite-plugin-solid": "^2",
    "typescript": "^5.7",
    "tailwindcss": "^3.4",
    "postcss": "^8",
    "autoprefixer": "^10",
    "tailwindcss-animate": "^1.0"
  }
}
```

## 5. File Structure for web/

Per eng spec §12A.2:
```
web/
├── package.json
├── pnpm-lock.yaml          # Generated by pnpm install
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.ts       # Tailwind v3 config with shadcn tokens
├── postcss.config.js
├── index.html               # Vite entry
├── src/
│   ├── index.tsx            # SolidJS entry (render to #root)
│   ├── App.tsx              # Root component with placeholder layout
│   ├── styles/
│   │   └── tokens.css       # ALL --sm-* CSS vars + shadcn HSL vars
│   ├── lib/
│   │   └── cn.ts            # clsx + twMerge utility
│   ├── features/            # Empty dirs for future features
│   │   ├── Chat/
│   │   └── IDE/
│   ├── components/          # For future shadcn-solid components
│   └── stores/              # For future SolidJS stores
├── tests/
│   └── e2e/                 # For future Playwright tests
└── dist/                    # Build output (gitignored)
```

## 6. Gotchas / Pitfalls

1. **Tailwind v3 vs v4**: shadcn-solid requires v3 config pattern (`tailwind.config.ts` + `postcss.config.js`). Do NOT use Tailwind v4's `@import "tailwindcss"` or `@tailwindcss/vite` plugin. Use `postcss` + `autoprefixer` pipeline instead.

2. **SolidJS uses `class` not `className`**: Unlike React/prototype1, SolidJS JSX uses HTML `class` attribute. The `cn()` utility works the same way.

3. **`pnpm build` must succeed**: `zig build web` runs `pnpm build` — the Vite build must produce `web/dist/index.html` without errors. Keep placeholder simple.

4. **prettier-check**: `zig build all` runs `prettier --check .` which will scan `web/` files. Either format with prettier or add `.prettierignore` entries. Since there's no `.prettierrc` in the repo, prettier will use defaults. Ensure generated files are properly formatted.

5. **`.gitignore` already covers `node_modules/`** (line 11 of root `.gitignore`). Need to add `web/dist/` or it's already covered by existing patterns. Check: `dist/` is already gitignored (line 4) but that's for root `dist/`. May need explicit `web/dist/` or it may be fine since `dist/` anywhere would match.

## 7. README Update

Current README (`README.md` lines 1-38) needs a web section. Add after the Build section:

```markdown
## Web App

Requires [pnpm](https://pnpm.io/) and [Node.js](https://nodejs.org/).

```bash
cd web
pnpm install
pnpm dev          # Dev server at http://localhost:5173
pnpm build        # Production build to web/dist/
```

Or via Zig:
```bash
zig build web     # Build web app (requires pnpm)
```
```

## 8. Token Math Contract (from design.md §2.3.1)

For CSS, the spec requires:
- `--sm-accent-rgb: 76, 141, 255;` (comma-separated for `rgba(var(--sm-accent-rgb), 0.12)`)
- `white@X%` = `rgba(255, 255, 255, X/100)` — applied as background colors
- `accent@X%` = `rgba(var(--sm-accent-rgb), X/100)`

## 9. Existing Patterns to Follow

- **Prototype1 globals.css**: Copy token definitions almost verbatim into `web/src/styles/tokens.css`
- **Prototype1 tailwind.config.ts**: Adapt for SolidJS (change content paths to `./src/**/*.{ts,tsx}`)
- **Prototype1 page.tsx layout**: Simplify for placeholder — keep the dual-pane concept with token usage

## 10. Open Questions

1. **shadcn-solid dark mode selector**: Uses `[data-kb-theme="dark"]` (Kobalte convention) vs prototype's class-based `darkMode: ['class']`. Since we're dark-only for now, put tokens in `:root` directly (no dark mode toggle needed yet).

2. **Font loading**: Prototype uses Google Fonts (Inter + JetBrains Mono). Spec says system fonts only (SF Pro, SF Mono). For web, system font stack is fine for scaffold: `font-family: system-ui, -apple-system, sans-serif` for UI and `ui-monospace, 'SF Mono', monospace` for code.

3. **PWA manifest**: Spec says "SolidJS Vite PWA". Should we add `vite-plugin-pwa` in scaffold or defer? Recommendation: defer — not in acceptance criteria.
