---
name: astro-dev
description: Comprehensive Astro development with Svelte, Tailwind v4, and Cloudflare Workers deployment
---

# Astro Development Skill

## Overview

Comprehensive guide for building modern web applications with Astro, Svelte, Tailwind CSS v4, and Cloudflare Workers deployment.

## Philosophy: Vanilla JS First

**Astro is built for content-focused websites that ship minimal JavaScript.** Before reaching for component islands:

1. **Use Astro components** - Static HTML with scoped styles, zero JS shipped
2. **Use vanilla JS** - `<script>` tags in Astro files for simple interactivity
3. **Use Svelte islands** - Only when you need reactive state or complex interactions

```astro
---
// GOOD: Vanilla JS for simple interactions
---
<button id="toggle">Toggle</button>
<div id="content" class="hidden">Content here</div>

<script>
  const button = document.getElementById('toggle');
  const content = document.getElementById('content');
  button?.addEventListener('click', () => {
    content?.classList.toggle('hidden');
  });
</script>
```

**When to use Svelte islands:**
- Complex forms with validation and state
- Real-time updates (websockets, polling)
- Heavy user interaction (drag-and-drop, rich editors)
- Components that need reactive data binding

**When vanilla JS is enough:**
- Toggle visibility (dropdowns, modals, accordions)
- Simple animations and transitions
- Form submission without complex validation
- Event handling without state management

## What This Skill Provides

### Automation Scripts
- **Project initialization** - Bootstrap new Astro projects with best practices
- **Content collections setup** - Generate type-safe content schemas
- **View Transitions integration** - Add smooth page transitions automatically

### Reference Documentation
- **Cloudflare Workers** - Workers-first deployment (NOT Pages)
- **Cloudflare D1** - Serverless SQLite database integration
- **Svelte integration** - Interactive islands and hydration strategies
- **Tailwind CSS v4** - CSS-first configuration without config files
- **Content Collections** - Type-safe content management
- **View Transitions** - Smooth page animations
- **GitHub Actions** - CI/CD automation

### Component Templates
- **BaseLayout** - Full page layout with header, footer, and View Transitions
- **Card** - Reusable card component with Tailwind styling
- **Button** - Svelte button with variants and sizes

## Quick Start

### Initialize New Project

**For Cloudflare Workers deployment (recommended):**
```bash
./scripts/init_astro_cloudflare.sh my-app
```

Creates:
- Astro project with SSR
- Svelte integration
- Tailwind CSS v4
- Cloudflare adapter configured
- wrangler.jsonc for Workers deployment

**For standard static site:**
```bash
./scripts/init_astro_standard.sh my-site
```

### Add Content Collections

```bash
python scripts/setup_content_collection.py blog
```

Creates:
- `src/content/blog/` directory
- Type-safe Zod schema in `src/content/config.ts`
- Example blog post

**Collection types:**
- `blog` - Blog posts with frontmatter
- `docs` - Documentation pages
- `products` - Product data (JSON)

### Add View Transitions

```bash
python scripts/add_view_transitions.py
```

Automatically adds View Transitions API to all layouts in `src/layouts/`.

## Common Workflows

### 1. Create Astro + Cloudflare Workers Site

```bash
# Initialize project
./scripts/init_astro_cloudflare.sh my-blog

cd my-blog

# Set up content collections
python ../scripts/setup_content_collection.py blog

# Add View Transitions
python ../scripts/add_view_transitions.py

# Start development
npm run dev

# Deploy to Cloudflare Workers
npx wrangler deploy
```

### 2. Add D1 Database

See `references/cloudflare-d1.md` for:
- Database creation
- Schema definition
- Query patterns
- Drizzle ORM integration

### 3. Build Interactive Components

See `references/svelte-integration.md` for:
- Client directives (load, idle, visible)
- Stores and state management
- Form handling
- Component communication

### 4. Style with Tailwind v4

See `references/tailwind-setup.md` for:
- CSS-first configuration
- Custom themes
- Dark mode
- OKLCH colors
- Container queries

## Deployment

### Cloudflare Workers (Recommended)

```bash
# One-time setup
npm install -g wrangler
wrangler login

# Deploy
npm run build
npx wrangler deploy
```

**Key points:**
- Uses `wrangler.jsonc` configuration
- Deploys to Cloudflare Workers (NOT Pages)
- Main entry: `./dist/_worker.js`
- Static assets served from `./dist`

See `references/cloudflare-workers.md` for:
- Bindings (KV, D1, R2)
- Environment variables
- TypeScript types
- SSR configuration

### GitHub Actions

See `references/github-actions.md` for:
- Automated deployments
- Preview deployments for PRs
- Security scanning
- Performance budgets

## Key Concepts

### Rendering Modes

```javascript
// astro.config.mjs

// Server-Side Rendering (all pages on-demand)
export default defineConfig({
  output: 'server',
});

// Hybrid (static by default, opt-in to SSR)
export default defineConfig({
  output: 'hybrid',
});

// Static (pre-rendered at build time)
export default defineConfig({
  output: 'static',
});
```

### File Structure

```
my-astro-app/
├── src/
│   ├── pages/              # File-based routing
│   │   ├── index.astro
│   │   ├── blog/
│   │   │   └── [...slug].astro
│   │   └── api/           # API endpoints
│   │       └── data.ts
│   ├── layouts/           # Page layouts
│   │   └── BaseLayout.astro
│   ├── components/        # Astro components (preferred)
│   │   └── Card.astro
│   ├── islands/           # Svelte islands (use sparingly)
│   │   └── Counter.svelte
│   ├── content/           # Content collections
│   │   ├── config.ts
│   │   └── blog/
│   ├── styles/            # Global CSS
│   │   └── global.css
│   └── env.d.ts           # TypeScript types
├── public/                # Static assets
│   └── .assetsignore      # Workers asset config
├── astro.config.mjs       # Astro configuration
├── wrangler.jsonc         # Cloudflare Workers config
├── package.json
└── tsconfig.json
```

### Client Directives

Control when Svelte components hydrate:

```astro
<!-- Hydrate immediately -->
<Counter client:load />

<!-- Hydrate when idle -->
<SocialShare client:idle />

<!-- Hydrate when visible -->
<Comments client:visible />

<!-- Hydrate on specific media query -->
<MobileMenu client:media="(max-width: 768px)" />

<!-- Client-only (no SSR) -->
<BrowserWidget client:only="svelte" />
```

### Cloudflare Runtime

Access Workers APIs in pages and API routes:

```astro
---
// In .astro files
const { env, cf, ctx } = Astro.locals.runtime;

// Use KV
const data = await env.MY_KV.get('key');

// Use D1
const { results } = await env.DB.prepare('SELECT * FROM users').all();

// Request properties
const country = cf.country;
---
```

## Best Practices

### Performance
1. **Use SSG when possible** - Pre-render static content
2. **Optimize images** - Use Astro's `<Image />` component
3. **Prefer vanilla JS** - Use `<script>` tags for simple interactions
4. **Minimize islands** - Use Svelte only where truly needed
5. **Leverage edge caching** - Set cache headers on API routes
6. **Use KV for caching** - Cache expensive operations

### Development
1. **Type everything** - Use TypeScript for better DX
2. **Validate content** - Use Zod schemas for content collections
3. **Test locally** - Use `platformProxy` for bindings in dev
4. **Generate types** - Run `wrangler types` after binding changes
5. **Follow conventions** - Use file-based routing

### Deployment
1. **Deploy to Workers** - Use Workers, not Pages (Cloudflare recommendation)
2. **Use environments** - staging/production in wrangler.jsonc
3. **Automate with CI/CD** - GitHub Actions for deployments
4. **Monitor performance** - Use Cloudflare Analytics
5. **Review logs** - Use `wrangler tail` for debugging

## Troubleshooting

### Common Issues

**Build Errors:**
- Run `npx astro check` for TypeScript errors
- Check Node.js version (18+)
- Clear `.astro` cache and rebuild

**Hydration Issues:**
- Ensure Svelte components have `client:*` directive
- Check for SSR-incompatible code (browser APIs)
- Use `client:only` if component can't be server-rendered

**Deployment Issues:**
- Verify `wrangler.jsonc` configuration
- Check `CLOUDFLARE_API_TOKEN` permissions
- Ensure bindings are configured correctly
- Review `wrangler tail` logs

**Tailwind Not Working:**
- Import `global.css` in layout
- Verify Vite plugin in `astro.config.mjs`
- Check `@import "tailwindcss"` at top of CSS

## Resources

### Documentation
- [Astro Docs](https://docs.astro.build)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Tailwind CSS v4](https://tailwindcss.com/docs/v4-alpha)
- [Svelte Docs](https://svelte.dev/docs)

### Tools
- [Astro VS Code Extension](https://marketplace.visualstudio.com/items?itemName=astro-build.astro-vscode)
- [Svelte VS Code Extension](https://marketplace.visualstudio.com/items?itemName=svelte.svelte-vscode)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/)
- [Drizzle Studio](https://orm.drizzle.team/drizzle-studio/overview)

### Reference Files
- `cloudflare-workers.md` - Workers deployment guide
- `cloudflare-d1.md` - D1 database setup
- `svelte-integration.md` - Svelte patterns
- `tailwind-setup.md` - Tailwind v4 config
- `content-collections.md` - Content management
- `view-transitions.md` - Page animations
- `github-actions.md` - CI/CD workflows

## Updating This Skill

Astro and its ecosystem evolve rapidly. To update:
1. Search for latest Astro documentation
2. Update reference files with new patterns
3. Add new scripts for common workflows
4. Test changes with real projects
5. Repackage the skill

## Version Information

This skill is current as of:
- **Astro** 5.x
- **Svelte** 5.x
- **Tailwind CSS** 4.x
- **Cloudflare Workers** (latest)
- **@astrojs/cloudflare** 11.x+

Last updated: December 2024

## Notes

- **Cloudflare Workers, NOT Pages** - This skill focuses exclusively on Workers deployment
- **Tailwind v4** - Uses CSS-first configuration (no tailwind.config.js)
- **Vanilla JS first** - Prefer `<script>` tags over Svelte for simple interactivity
- **Type-safe** - Leverages TypeScript throughout
- **Modern stack** - Latest versions and best practices
