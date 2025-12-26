# View Transitions in Astro

## Overview

Astro's View Transitions API provides smooth page transitions using the browser's native View Transitions API with a fallback for unsupported browsers.

## Setup

### Add to Layout

```astro
---
// src/layouts/Layout.astro
import { ViewTransitions } from 'astro:transitions';
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width" />
    <title>My Site</title>
    <ViewTransitions />
  </head>
  <body>
    <slot />
  </body>
</html>
```

That's it! Pages now transition smoothly.

## Transition Directives

### transition:animate

Control animation style:

```astro
<main transition:animate="slide">
  <slot />
</main>
```

**Built-in animations:**
- `fade` - Cross-fade (default)
- `slide` - Slide from right
- `none` - No animation

### transition:persist

Keep elements across page transitions:

```astro
<header transition:persist>
  <nav>...</nav>
</header>

<video transition:persist controls>
  <source src="/video.mp4" />
</video>
```

Use cases:
- Navigation menus
- Audio/video players
- Search boxes
- Shopping carts

### transition:name

Give elements unique transition identities:

```astro
<img 
  src="/hero.jpg"
  transition:name="hero-image"
  alt="Hero"
/>
```

```astro
<!-- On next page -->
<img 
  src="/hero-detail.jpg"
  transition:name="hero-image"
  alt="Hero Detail"
/>
```

Elements with the same `transition:name` morph between pages.

### transition:persist-props

Keep component state but update props:

```astro
<Counter 
  client:load
  count={initialCount}
  transition:persist-props
/>
```

## Custom Animations

### CSS Animations

```css
@keyframes slide-from-right {
  from {
    transform: translateX(100%);
  }
}

@keyframes slide-to-left {
  to {
    transform: translateX(-100%);
  }
}

::view-transition-old(slide) {
  animation: 300ms ease-out both slide-to-left;
}

::view-transition-new(slide) {
  animation: 300ms ease-out both slide-from-right;
}
```

```astro
<main transition:animate="slide">
  Content
</main>
```

### Custom Animation Names

```astro
<div transition:animate="custom-fade">
  Content
</div>
```

```css
@keyframes custom-fade-in {
  from { opacity: 0; scale: 0.9; }
}

@keyframes custom-fade-out {
  to { opacity: 0; scale: 1.1; }
}

::view-transition-old(custom-fade) {
  animation: 200ms ease-in both custom-fade-out;
}

::view-transition-new(custom-fade) {
  animation: 200ms ease-out both custom-fade-in;
}
```

## Lifecycle Events

### Navigation Events

```typescript
// Listen for navigation
document.addEventListener('astro:before-preparation', (e) => {
  console.log('About to prepare transition');
});

document.addEventListener('astro:after-preparation', (e) => {
  console.log('Preparation complete');
});

document.addEventListener('astro:before-swap', (e) => {
  console.log('About to swap DOM');
});

document.addEventListener('astro:after-swap', (e) => {
  console.log('DOM swapped');
  // Reset scroll, reinitialize scripts, etc.
});

document.addEventListener('astro:page-load', (e) => {
  console.log('Page fully loaded');
});
```

### Programmatic Navigation

```astro
<button id="navigate">Go to About</button>

<script>
  import { navigate } from 'astro:transitions/client';
  
  document.getElementById('navigate')?.addEventListener('click', () => {
    navigate('/about');
  });
</script>
```

## Advanced Patterns

### Conditional Transitions

```astro
---
const enableTransitions = true;
---

<html>
  <head>
    {enableTransitions && <ViewTransitions />}
  </head>
</html>
```

### Persist State Across Pages

```astro
<!-- Component that persists -->
<ThemeToggle 
  client:load
  transition:persist
  transition:name="theme-toggle"
/>
```

### Scroll Position

```typescript
// Preserve scroll position for specific elements
document.addEventListener('astro:after-swap', () => {
  const scrollableEl = document.getElementById('content');
  if (scrollableEl) {
    const savedPosition = sessionStorage.getItem('scroll-position');
    if (savedPosition) {
      scrollableEl.scrollTop = parseInt(savedPosition);
    }
  }
});

document.addEventListener('astro:before-preparation', () => {
  const scrollableEl = document.getElementById('content');
  if (scrollableEl) {
    sessionStorage.setItem('scroll-position', scrollableEl.scrollTop.toString());
  }
});
```

### Loading States

```astro
<div id="loading-indicator" class="hidden">
  Loading...
</div>

<script>
  document.addEventListener('astro:before-preparation', () => {
    document.getElementById('loading-indicator')?.classList.remove('hidden');
  });

  document.addEventListener('astro:page-load', () => {
    document.getElementById('loading-indicator')?.classList.add('hidden');
  });
</script>
```

## Fallback Behavior

View Transitions gracefully fall back to instant page loads in:
- Browsers without View Transitions API support
- Users with reduced motion preferences
- Pages with errors during transition

## Performance Tips

1. **Keep animations short** - 200-400ms ideal
2. **Use transform/opacity** - GPU-accelerated properties
3. **Minimize transition:persist** - Only for truly persistent UI
4. **Test on slower devices** - Ensure smooth performance
5. **Respect prefers-reduced-motion** - Disable animations when requested

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  ::view-transition-old(*),
  ::view-transition-new(*) {
    animation: none !important;
  }
}
```

## Common Use Cases

### Image Gallery

```astro
<!-- Gallery page -->
{images.map(img => (
  <a href={`/image/${img.id}`}>
    <img 
      src={img.thumb}
      transition:name={`image-${img.id}`}
      alt={img.alt}
    />
  </a>
))}
```

```astro
<!-- Detail page -->
<img 
  src={image.full}
  transition:name={`image-${image.id}`}
  alt={image.alt}
/>
```

### Persistent Media Player

```astro
<audio 
  controls
  transition:persist
  transition:name="audio-player"
>
  <source src="/podcast.mp3" />
</audio>
```

### Page-Specific Animations

```astro
---
// Different animations per page
const animations = {
  home: 'fade',
  about: 'slide',
  blog: 'none',
};

const currentPage = Astro.url.pathname.split('/')[1] || 'home';
const animation = animations[currentPage] || 'fade';
---

<main transition:animate={animation}>
  <slot />
</main>
```

## Debugging

### View Transition Names

```typescript
// Log all transition names
document.addEventListener('astro:before-preparation', () => {
  document.querySelectorAll('[data-astro-transition-scope]').forEach(el => {
    console.log('Transition element:', el, el.getAttribute('data-astro-transition-scope'));
  });
});
```

### Transition Duration

```css
/* Slow down transitions for debugging */
::view-transition-old(*),
::view-transition-new(*) {
  animation-duration: 2s !important;
}
```

## Resources

- [Astro View Transitions Docs](https://docs.astro.build/en/guides/view-transitions/)
- [View Transitions API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API)
- [Browser Support](https://caniuse.com/view-transitions)

## Best Practices

1. **Start with defaults** - Built-in animations work well
2. **Use meaningful names** - transition:name="product-hero"
3. **Test fallbacks** - Ensure site works without transitions
4. **Keep it subtle** - Don't overdo animations
5. **Respect user preferences** - Honor prefers-reduced-motion
6. **Persist sparingly** - Only for truly shared UI elements
7. **Test performance** - Ensure smooth on all devices

## Troubleshooting

**Issue: Transitions not working**
- Ensure <ViewTransitions /> is in <head>
- Check both pages have the component
- Verify no JavaScript errors

**Issue: Elements jumping**
- Give elements stable positioning
- Use transition:name for morphing elements
- Check for layout shifts

**Issue: State lost between pages**
- Use transition:persist on interactive components
- Ensure component has client: directive
- Check transition:name matches between pages
