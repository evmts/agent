# Tailwind CSS v4 in Astro

## Overview

Tailwind CSS v4 uses a CSS-first configuration approach. No more `tailwind.config.js` - everything is configured in CSS using the `@theme` directive.

## Installation

```bash
npm install -D tailwindcss @tailwindcss/vite
```

## Configuration

### astro.config.mjs

```javascript
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  vite: {
    plugins: [tailwindcss()],
  },
});
```

### Global CSS

**src/styles/global.css:**
```css
@import "tailwindcss";

/* Plugins */
@plugin "@tailwindcss/typography";
@plugin "@tailwindcss/forms";

/* Dark mode */
@custom-variant dark (&:where(.dark, .dark *));

/* Theme customization */
@theme {
  /* Colors - use OKLCH for better perceptual uniformity */
  --color-primary-500: oklch(0.60 0.15 220);
  --color-secondary-500: oklch(0.55 0.20 340);
  
  /* Fonts */
  --font-sans: system-ui, -apple-system, sans-serif;
  --font-serif: Georgia, "Times New Roman", serif;
  --font-mono: "Fira Code", Consolas, monospace;
  
  /* Spacing (optional overrides) */
  --spacing-18: 4.5rem;
  
  /* Breakpoints (optional custom) */
  --breakpoint-3xl: 1920px;
}

/* Dark mode theme overrides */
.dark @theme {
  --color-primary-500: oklch(0.70 0.15 220);
}
```

### Import in Layout

```astro
---
// src/layouts/Layout.astro
import '../styles/global.css';
---

<!doctype html>
<html lang="en">
  <head>...</head>
  <body>
    <slot />
  </body>
</html>
```

## Key Differences from v3

### 1. No Config File

**v3:**
```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: '#3b82f6',
      },
    },
  },
};
```

**v4:**
```css
/* global.css */
@theme {
  --color-primary: #3b82f6;
}
```

### 2. CSS Variables Exposed

All theme values are now CSS variables:

```css
.my-element {
  color: var(--color-primary-500);
  font-size: var(--font-size-lg);
  padding: var(--spacing-4);
}
```

### 3. OKLCH Colors

Use OKLCH for better color interpolation:

```css
@theme {
  --color-primary-500: oklch(0.60 0.15 220);
  /* Lightness, Chroma, Hue */
}
```

### 4. Plugin Loading

**v3:**
```javascript
plugins: [require('@tailwindcss/typography')]
```

**v4:**
```css
@plugin "@tailwindcss/typography";
```

## Common Patterns

### Custom Colors

```css
@theme {
  --color-brand-50: oklch(0.98 0.02 220);
  --color-brand-100: oklch(0.95 0.04 220);
  --color-brand-200: oklch(0.90 0.08 220);
  /* ... through to 900 */
  --color-brand-900: oklch(0.20 0.10 220);
  --color-brand-950: oklch(0.15 0.08 220);
}
```

Usage:
```html
<div class="bg-brand-500 text-brand-50">
  Brand colors
</div>
```

### Custom Fonts

```css
@import "tailwindcss";

@theme {
  --font-display: "Playfair Display", serif;
  --font-body: "Inter", sans-serif;
}
```

```html
<h1 class="font-display">Heading</h1>
<p class="font-body">Body text</p>
```

### Custom Breakpoints

```css
@theme {
  --breakpoint-xs: 475px;
  --breakpoint-3xl: 1920px;
}
```

```html
<div class="xs:text-sm 3xl:text-2xl">
  Responsive text
</div>
```

### Dark Mode

```css
@custom-variant dark (&:where(.dark, .dark *));

@theme {
  --color-background: white;
  --color-text: black;
}

.dark @theme {
  --color-background: #0a0a0a;
  --color-text: white;
}
```

```html
<body class="bg-background text-text">
  <!-- Toggle dark mode by adding/removing 'dark' class -->
</body>
```

### Custom Utilities

```css
@utility text-balance {
  text-wrap: balance;
}

@utility text-pretty {
  text-wrap: pretty;
}
```

```html
<h1 class="text-balance">
  Balanced headline text
</h1>
```

## Plugins

### Typography

```css
@plugin "@tailwindcss/typography";
```

```html
<article class="prose lg:prose-xl">
  <h1>Article Title</h1>
  <p>Content...</p>
</article>
```

### Forms

```css
@plugin "@tailwindcss/forms";
```

```html
<form>
  <input type="email" class="form-input" />
  <textarea class="form-textarea"></textarea>
  <select class="form-select">...</select>
</form>
```

### Container Queries

Built-in in v4! No plugin needed:

```html
<div class="@container">
  <div class="@sm:text-lg @lg:text-xl">
    Responds to container size
  </div>
</div>
```

## Advanced Features

### Multi-Theme Support

```css
@custom-variant theme-blue (.theme-blue *);
@custom-variant theme-green (.theme-green *);

@theme {
  --color-accent: oklch(0.60 0.15 220);
}

.theme-blue @theme {
  --color-accent: oklch(0.60 0.15 240);
}

.theme-green @theme {
  --color-accent: oklch(0.60 0.15 140);
}
```

### Custom Animations

```css
@keyframes slide-in {
  from {
    transform: translateX(-100%);
  }
  to {
    transform: translateX(0);
  }
}

@theme {
  --animate-slide-in: slide-in 0.5s ease-out;
}
```

```html
<div class="animate-slide-in">
  Animated element
</div>
```

### Responsive Design

```html
<!-- Mobile first -->
<div class="text-sm md:text-base lg:text-lg xl:text-xl">
  Responsive text
</div>

<!-- Arbitrary values -->
<div class="w-[42rem] max-w-[calc(100%-2rem)]">
  Custom width
</div>

<!-- Container queries -->
<div class="@container">
  <div class="@md:columns-2 @lg:columns-3">
    Responsive columns
  </div>
</div>
```

## Component Patterns

### Button Variants

```tsx
// src/components/Button.tsx
interface Props {
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  children: React.ReactNode;
}

const variants = {
  primary: 'bg-primary-500 text-white hover:bg-primary-600',
  secondary: 'bg-gray-200 text-gray-900 hover:bg-gray-300',
  ghost: 'bg-transparent hover:bg-gray-100',
};

const sizes = {
  sm: 'px-3 py-1.5 text-sm',
  md: 'px-4 py-2 text-base',
  lg: 'px-6 py-3 text-lg',
};

export default function Button({ 
  variant = 'primary', 
  size = 'md', 
  children 
}: Props) {
  return (
    <button 
      className={`
        rounded-md font-medium transition-colors
        ${variants[variant]}
        ${sizes[size]}
      `}
    >
      {children}
    </button>
  );
}
```

### Card Component

```astro
---
// src/components/Card.astro
interface Props {
  title: string;
  hoverable?: boolean;
}

const { title, hoverable = false } = Astro.props;
---

<div class={`
  bg-white dark:bg-gray-800 
  rounded-lg shadow-md p-6
  ${hoverable ? 'hover:shadow-lg transition-shadow' : ''}
`}>
  <h3 class="text-xl font-bold mb-2 text-gray-900 dark:text-white">
    {title}
  </h3>
  <div class="text-gray-600 dark:text-gray-300">
    <slot />
  </div>
</div>
```

## Best Practices

### 1. Use Semantic Tokens

```css
/* Instead of using colors directly everywhere */
@theme {
  --color-background: white;
  --color-foreground: black;
  --color-primary: oklch(0.60 0.15 220);
  --color-muted: #6b7280;
}
```

### 2. Leverage Custom Variants

```css
@custom-variant hocus (&:hover, &:focus);
@custom-variant group-hocus (.group:hover &, .group:focus &);
```

```html
<button class="hocus:scale-105">Hover or focus to scale</button>
```

### 3. Use Container Queries

```html
<!-- Responds to parent container, not viewport -->
<div class="@container">
  <div class="@sm:flex @md:grid @lg:columns-2">
    Content adapts to container
  </div>
</div>
```

### 4. Consistent Spacing

```css
@theme {
  --spacing-section: 5rem;
  --spacing-component: 2rem;
}
```

### 5. Typography Scale

```css
@theme {
  --font-size-xs: 0.75rem;
  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-lg: 1.125rem;
  --font-size-xl: 1.25rem;
  --font-size-2xl: 1.5rem;
  --font-size-3xl: 1.875rem;
  --font-size-4xl: 2.25rem;
}
```

## Performance

Tailwind v4 is significantly faster than v3:

- **5-100x faster** builds
- Uses native CSS features
- Better caching
- Smaller output

## Migration from v3

1. Remove `tailwind.config.js`
2. Install `@tailwindcss/vite`
3. Update Astro config to use Vite plugin
4. Move theme config to CSS with `@theme`
5. Update plugins to use `@plugin` directive
6. Update custom variants to `@custom-variant`

## Resources

- [Tailwind CSS v4 Alpha Docs](https://tailwindcss.com/docs/v4-alpha)
- [OKLCH Color Picker](https://oklch.com/)
- [Tailwind Play (v4)](https://play.tailwindcss.com/)

## Troubleshooting

**Issue: Styles not applying**
- Ensure global.css is imported in layout
- Check Vite plugin is loaded in astro.config.mjs
- Verify `@import "tailwindcss"` is at top of CSS

**Issue: Dark mode not working**
- Add `@custom-variant dark` directive
- Toggle `dark` class on html/body element
- Check dark theme overrides in CSS

**Issue: Custom colors not recognized**
- Verify color definitions in `@theme`
- Check naming convention (--color-name-shade)
- Ensure no typos in class names
