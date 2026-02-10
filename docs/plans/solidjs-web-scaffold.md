# Plan: solidjs-web-scaffold

## Summary

Scaffold `web/` as a SolidJS + Vite + Tailwind v3 PWA with all Smithers design tokens as CSS variables. The build system is already wired — `zig build web` checks for `web/` and runs `pnpm install && pnpm build`. Creating the directory with a valid project makes it work immediately.

## Key Decisions

1. **Tailwind v3 (not v4)** — shadcn-solid requires v3's `tailwind.config.ts` pattern. v4's CSS-first config is incompatible.
2. **Manual Vite + SolidJS setup** — not SolidStart. Plain `vite` + `vite-plugin-solid`.
3. **Dark-only tokens in `:root`** — no dark mode toggle needed yet. Tokens go directly in `:root`.
4. **System fonts** — `system-ui, -apple-system, sans-serif` for UI, `ui-monospace, 'SF Mono', monospace` for code.
5. **Defer PWA manifest** — `vite-plugin-pwa` not in acceptance criteria.
6. **No build.zig changes** — already wired at line 132.
7. **`zig build all` unaffected** — web not in `all` step. Only risk: `prettier --check .` scanning `web/` files. Must add `.prettierignore` to exclude `pnpm-lock.yaml`.

## Implementation Steps

### Step 0: Create .prettierignore (prevent `zig build all` breakage)

`prettier --check .` (in `zig build all`) will scan `web/` files. Need `.prettierignore` to exclude generated files (`pnpm-lock.yaml`). All hand-written files will be prettier-formatted.

**File:** `.prettierignore` (new)

### Step 1: Create web/package.json with all dependencies

Core manifest with SolidJS, Vite, Tailwind v3, and shadcn-solid infrastructure deps.

**File:** `web/package.json` (new)

Dependencies:
- `solid-js` ^1.9
- `class-variance-authority` ^0.7.1
- `clsx` ^2.1.1
- `tailwind-merge` ^2.5.5

Dev dependencies:
- `vite` ^6
- `vite-plugin-solid` ^2
- `typescript` ^5.7
- `tailwindcss` ^3.4
- `postcss` ^8
- `autoprefixer` ^10
- `tailwindcss-animate` ^1.0

Scripts: `dev`, `build`, `preview`

### Step 2: Create Vite + TypeScript + PostCSS config files

Three config files that wire SolidJS, Tailwind v3, and TypeScript together.

**Files:**
- `web/vite.config.ts` — `vite-plugin-solid`, build output to `dist/`
- `web/tsconfig.json` — SolidJS JSX, strict mode, path aliases
- `web/postcss.config.js` — `tailwindcss` + `autoprefixer`

### Step 3: Create tailwind.config.ts with shadcn-solid token mapping

Adapted from prototype1's config. Content paths changed to `./src/**/*.{ts,tsx}`. HSL-based shadcn color mapping preserved for shadcn-solid component compatibility.

**File:** `web/tailwind.config.ts` (new)

### Step 4: Create tokens.css with ALL Smithers design tokens

The core deliverable. ALL `--sm-*` variables from design spec + shadcn HSL overrides + syntax highlighting + accent-rgb composite token. Verbatim from prototype1/app/globals.css with additions from design.md Token Math Contract.

**File:** `web/src/styles/tokens.css` (new)

Includes:
- Smithers surface/sidebar/pill/titlebar/bubble/input tokens
- Semantic colors (accent, success, warning, danger, info)
- Text opacity levels (primary, secondary, tertiary)
- Syntax highlighting palette (Nova-inspired)
- `--sm-accent-rgb: 76, 141, 255` (for rgba composition)
- shadcn HSL tokens (background, foreground, primary, etc.)
- Typography spacing tokens (`--sm-type-xs` through `--sm-type-xl`)
- Spacing tokens (`--sm-space-4` through `--sm-space-32`)
- Radius tokens (`--sm-radius-4` through `--sm-radius-16`)
- Base styles (body bg, color, scrollbar)

### Step 5: Create cn.ts utility

Standard shadcn utility: `clsx` + `tailwind-merge`. Required for all future shadcn-solid components.

**File:** `web/src/lib/cn.ts` (new)

### Step 6: Create SolidJS entry point (index.html + index.tsx)

Vite entry HTML + SolidJS render mount.

**Files:**
- `web/index.html` — HTML shell with `<div id="root">`, imports `/src/index.tsx`
- `web/src/index.tsx` — `render(() => <App />, document.getElementById("root")!)`

### Step 7: Create App.tsx placeholder layout

Dual-pane Chat + IDE placeholder that demonstrates tokens are working. Simplified from prototype1/app/page.tsx, converted to SolidJS (`class` not `className`). Uses `--sm-*` variables throughout: backgrounds, borders, text colors, bubbles.

**File:** `web/src/App.tsx` (new)

Layout:
- Full-height flex container with `--sm-base` bg
- Top bar with "Smithers v2" pill badge using `--sm-pill-*` tokens
- Left pane (45%): Chat placeholder — sidebar bg (`--sm-sidebar-bg`), mode bar, message area with sample bubbles (`--sm-bubble-*`)
- Right pane (55%): IDE placeholder — file tree bg (`--sm-surface1`), editor area (`--sm-surface1`), tab bar (`--sm-surface2`)
- All text uses `--sm-text-*` opacity tokens

### Step 8: Create empty feature directory structure

Placeholder directories per eng spec §12A.2. `.gitkeep` files so git tracks empty dirs.

**Files:**
- `web/src/features/Chat/.gitkeep`
- `web/src/features/IDE/.gitkeep`
- `web/src/components/.gitkeep`
- `web/src/stores/.gitkeep`
- `web/tests/e2e/.gitkeep`

### Step 9: Update README.md with web app quickstart

Add "Web App" section after Build section with pnpm install/dev/build instructions and `zig build web` reference.

**File:** `README.md` (modify)

### Step 10: Verify `zig build web` succeeds

Run `zig build web` and confirm:
- No "skipping web" message
- `web/dist/index.html` exists
- `web/dist/assets/` contains JS and CSS bundles

### Step 11: Verify `zig build all` still passes

Run `zig build all` and confirm:
- Zig build/test passes (unchanged)
- `prettier --check .` passes (web files formatted, lock file ignored)
- `zig fmt --check .` passes (no Zig changes)

## Files to Create

1. `.prettierignore`
2. `web/package.json`
3. `web/vite.config.ts`
4. `web/tsconfig.json`
5. `web/postcss.config.js`
6. `web/tailwind.config.ts`
7. `web/src/styles/tokens.css`
8. `web/src/lib/cn.ts`
9. `web/index.html`
10. `web/src/index.tsx`
11. `web/src/App.tsx`
12. `web/src/features/Chat/.gitkeep`
13. `web/src/features/IDE/.gitkeep`
14. `web/src/components/.gitkeep`
15. `web/src/stores/.gitkeep`
16. `web/tests/e2e/.gitkeep`

## Files to Modify

1. `README.md` — add web quickstart section

## Tests

No Zig or Swift changes, so no unit tests needed for this ticket. Validation is:
1. `zig build web` succeeds (produces `web/dist/index.html`)
2. `zig build all` passes (prettier-clean, no regressions)
3. Manual: tokens render visibly in placeholder (colors match design spec)

Future tickets will add Playwright e2e tests in `web/tests/e2e/`.

## Risks

1. **pnpm version mismatch** — `pnpm install` may produce different lock files across pnpm versions. Pin `packageManager` field in `package.json` to avoid CI drift.
2. **prettier scanning pnpm-lock.yaml** — Large generated file. Must be in `.prettierignore`.
3. **Tailwind v3 PostCSS compatibility** — Tailwind v3 needs `postcss` + `autoprefixer` peer deps. Must be explicit in devDependencies.
4. **SolidJS JSX transform** — `vite-plugin-solid` must be first plugin in Vite config for proper JSX handling.
5. **`dist/` gitignore coverage** — Root `.gitignore` has `dist/` which covers `web/dist/` via glob. Verified OK.
