# Public

Static assets served directly without processing.

## Files

| File | Purpose | Size |
|------|---------|------|
| `favicon.svg` | Browser favicon | SVG |
| `pwa-192x192.svg` | PWA icon (192x192) | SVG |
| `pwa-512x512.svg` | PWA icon (512x512) | SVG |

## Usage

Files in this directory are served from the root URL:

```html
<!-- In HTML -->
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />

<!-- PWA manifest -->
<link rel="manifest" href="/manifest.json" />
```

## PWA Icons

Icons used for Progressive Web App installation:
- `pwa-192x192.svg` - Standard app icon
- `pwa-512x512.svg` - High-res app icon

Both are SVG for scalability and dark mode support.

## Adding Assets

New static assets go here:
1. Add file to `public/`
2. Reference from root path: `/filename.ext`
3. No import/processing needed

Examples:
- Images: `/logo.svg`
- Fonts: `/fonts/custom.woff2`
- Documents: `/docs/guide.pdf`
- Manifests: `/manifest.json`

## Build Output

During build, `public/` contents are copied to `dist/` unchanged. No optimization or transformation.
