# Layouts

Page layout wrapper for Plue UI.

## Files

| File | Purpose |
|------|---------|
| `Layout.astro` | Main page layout with head, body, footer |

## Layout.astro

Base layout used by all pages:

```astro
---
import Layout from '../layouts/Layout.astro';
---
<Layout title="Page Title" description="Optional description">
  <!-- Page content here -->
</Layout>
```

### Props

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `title` | string | Yes | Page title (shown in browser tab) |
| `description` | string | No | Meta description (default: "Minimal git hosting") |

### Features

- Dark mode color scheme
- View Transitions API for smooth navigation
- PWA support (reload prompt)
- Toast notification system
- Footer component
- Canonical URL meta tags
- Responsive viewport settings

### Included Components

- `Footer.astro` - Site footer
- `ReloadPrompt.astro` - PWA update notification
- `ToastContainer.astro` - Global toast manager

### Global Styles

Layout includes global CSS with:
- View transition animations (120ms cubic-bezier)
- Dark theme variables
- Typography and spacing
- Form controls
- Utility classes

### Scripts

Automatically includes:
- `lib/toast.ts` - Toast notification handler
