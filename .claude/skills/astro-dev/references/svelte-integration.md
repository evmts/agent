# Svelte Integration in Astro

## Overview

Astro supports Svelte as a UI framework for interactive islands. This guide covers best practices for using Svelte components in Astro projects.

**Remember: Prefer vanilla JS first!** Only use Svelte when you need:
- Reactive state management
- Complex form handling
- Real-time updates
- Heavy user interaction

## Installation

```bash
npx astro add svelte

# Or manual
npm install svelte @astrojs/svelte
```

**astro.config.mjs:**
```javascript
import svelte from '@astrojs/svelte';

export default defineConfig({
  integrations: [svelte()],
});
```

## Client Directives

Control when Svelte components hydrate on the client.

### client:load

Hydrate immediately on page load:

```astro
---
import Counter from '../islands/Counter.svelte';
---
<Counter client:load />
```

**Use when:** Component needed immediately (above fold, critical UI).

### client:idle

Hydrate when browser is idle:

```astro
<SocialShare client:idle />
```

**Use when:** Non-critical components (social buttons, newsletter).

### client:visible

Hydrate when component enters viewport:

```astro
<Comments client:visible />
```

**Use when:** Below-fold content, lazy-loaded sections.

### client:media

Hydrate based on media query:

```astro
<MobileMenu client:media="(max-width: 768px)" />
```

**Use when:** Responsive components (mobile-only nav).

### client:only

Skip server rendering, client-only:

```astro
<ClientOnlyWidget client:only="svelte" />
```

**Use when:** Browser APIs required, no SSR possible.

## Svelte 5 Component Patterns

### Simple Interactive Component

```svelte
<!-- src/islands/Counter.svelte -->
<script lang="ts">
  let count = $state(0);
</script>

<div>
  <p>Count: {count}</p>
  <button onclick={() => count++}>
    Increment
  </button>
</div>
```

```astro
---
// src/pages/index.astro
import Counter from '../islands/Counter.svelte';
---
<Counter client:load />
```

### Passing Props

```svelte
<!-- src/islands/Greeting.svelte -->
<script lang="ts">
  interface Props {
    name: string;
    age?: number;
  }

  let { name, age }: Props = $props();
</script>

<div>
  <h2>Hello, {name}!</h2>
  {#if age}
    <p>Age: {age}</p>
  {/if}
</div>
```

```astro
---
import Greeting from '../islands/Greeting.svelte';
---
<Greeting name="Alice" age={30} client:load />
```

### Passing Children (Slots)

```svelte
<!-- src/islands/Card.svelte -->
<script lang="ts">
  interface Props {
    title: string;
  }

  let { title }: Props = $props();
</script>

<div class="border rounded-lg p-4">
  <h3 class="text-xl font-bold mb-2">{title}</h3>
  <div>
    <slot />
  </div>
</div>
```

```astro
<Card title="Welcome" client:load>
  <p>This is the card content</p>
</Card>
```

## Reactivity with $state and $derived

### Basic State

```svelte
<script lang="ts">
  let todos = $state<string[]>([]);
  let input = $state('');

  function addTodo() {
    if (input.trim()) {
      todos = [...todos, input];
      input = '';
    }
  }
</script>

<div>
  <input
    bind:value={input}
    onkeypress={(e) => e.key === 'Enter' && addTodo()}
  />
  <button onclick={addTodo}>Add</button>
  <ul>
    {#each todos as todo, i}
      <li>{todo}</li>
    {/each}
  </ul>
</div>
```

### Derived State

```svelte
<script lang="ts">
  let items = $state(['apple', 'banana', 'cherry']);
  let filter = $state('');

  let filteredItems = $derived(
    items.filter(item => item.includes(filter))
  );
</script>

<input bind:value={filter} placeholder="Filter..." />
<ul>
  {#each filteredItems as item}
    <li>{item}</li>
  {/each}
</ul>
```

### Effects

```svelte
<script lang="ts">
  let data = $state(null);
  let loading = $state(true);

  $effect(() => {
    fetch('/api/data')
      .then(res => res.json())
      .then(json => {
        data = json;
        loading = false;
      });
  });
</script>

{#if loading}
  <div>Loading...</div>
{:else}
  <div>{JSON.stringify(data)}</div>
{/if}
```

## Stores for Shared State

### Creating a Store

```ts
// src/stores/theme.ts
import { writable } from 'svelte/store';

export type Theme = 'light' | 'dark';

function createThemeStore() {
  const { subscribe, set, update } = writable<Theme>('light');

  return {
    subscribe,
    toggle: () => update(t => t === 'light' ? 'dark' : 'light'),
    set,
  };
}

export const theme = createThemeStore();
```

### Using a Store

```svelte
<!-- src/islands/ThemeToggle.svelte -->
<script lang="ts">
  import { theme } from '../stores/theme';
</script>

<button onclick={theme.toggle}>
  Current theme: {$theme}
</button>
```

### Persisted Store

```ts
// src/stores/persisted.ts
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export function persisted<T>(key: string, initialValue: T) {
  const stored = browser ? localStorage.getItem(key) : null;
  const initial = stored ? JSON.parse(stored) : initialValue;

  const store = writable<T>(initial);

  store.subscribe(value => {
    if (browser) {
      localStorage.setItem(key, JSON.stringify(value));
    }
  });

  return store;
}
```

## Form Handling

### Basic Form

```svelte
<script lang="ts">
  let form = $state({
    name: '',
    email: '',
    message: '',
  });
  let submitting = $state(false);

  async function handleSubmit(e: Event) {
    e.preventDefault();
    submitting = true;

    const response = await fetch('/api/contact', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    });

    if (response.ok) {
      alert('Message sent!');
      form = { name: '', email: '', message: '' };
    }
    submitting = false;
  }
</script>

<form onsubmit={handleSubmit} class="space-y-4">
  <input
    type="text"
    bind:value={form.name}
    placeholder="Name"
    required
  />
  <input
    type="email"
    bind:value={form.email}
    placeholder="Email"
    required
  />
  <textarea
    bind:value={form.message}
    placeholder="Message"
    required
  />
  <button type="submit" disabled={submitting}>
    {submitting ? 'Sending...' : 'Send'}
  </button>
</form>
```

### Form Validation

```svelte
<script lang="ts">
  let email = $state('');
  let touched = $state(false);

  let isValid = $derived(
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  );
  let showError = $derived(touched && !isValid);
</script>

<input
  type="email"
  bind:value={email}
  onblur={() => touched = true}
  class:error={showError}
/>
{#if showError}
  <p class="text-red-500">Please enter a valid email</p>
{/if}
```

## Component Communication

### Events

```svelte
<!-- Child.svelte -->
<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher<{
    select: { id: number };
  }>();

  function handleClick(id: number) {
    dispatch('select', { id });
  }
</script>

<button onclick={() => handleClick(1)}>Select</button>
```

```svelte
<!-- Parent.svelte -->
<script lang="ts">
  import Child from './Child.svelte';

  function handleSelect(e: CustomEvent<{ id: number }>) {
    console.log('Selected:', e.detail.id);
  }
</script>

<Child on:select={handleSelect} />
```

### Callback Props (Svelte 5 preferred)

```svelte
<!-- Child.svelte -->
<script lang="ts">
  interface Props {
    onSelect?: (id: number) => void;
  }

  let { onSelect }: Props = $props();
</script>

<button onclick={() => onSelect?.(1)}>Select</button>
```

```svelte
<!-- Parent.svelte -->
<script lang="ts">
  import Child from './Child.svelte';
</script>

<Child onSelect={(id) => console.log('Selected:', id)} />
```

## Common Patterns

### Modal Dialog

```svelte
<script lang="ts">
  let isOpen = $state(false);
</script>

<button onclick={() => isOpen = true}>Open Modal</button>

{#if isOpen}
  <div class="fixed inset-0 bg-black/50 flex items-center justify-center">
    <div class="bg-white p-6 rounded-lg">
      <h2>Modal Title</h2>
      <p>Modal content here</p>
      <button onclick={() => isOpen = false}>Close</button>
    </div>
  </div>
{/if}
```

### Tabs

```svelte
<script lang="ts">
  const tabs = ['Tab 1', 'Tab 2', 'Tab 3'];
  let active = $state(0);
</script>

<div>
  <div class="flex gap-2">
    {#each tabs as tab, i}
      <button
        onclick={() => active = i}
        class:font-bold={active === i}
      >
        {tab}
      </button>
    {/each}
  </div>
  <div class="mt-4">
    Content for {tabs[active]}
  </div>
</div>
```

### Accordion

```svelte
<script lang="ts">
  interface Props {
    items: { title: string; content: string }[];
  }

  let { items }: Props = $props();
  let openIndex = $state<number | null>(null);

  function toggle(index: number) {
    openIndex = openIndex === index ? null : index;
  }
</script>

<div class="space-y-2">
  {#each items as item, i}
    <div class="border rounded">
      <button
        onclick={() => toggle(i)}
        class="w-full p-4 text-left font-medium"
      >
        {item.title}
      </button>
      {#if openIndex === i}
        <div class="p-4 border-t">
          {item.content}
        </div>
      {/if}
    </div>
  {/each}
</div>
```

### Dropdown

```svelte
<script lang="ts">
  let isOpen = $state(false);
  let selected = $state('');

  const options = ['Option 1', 'Option 2', 'Option 3'];

  function select(option: string) {
    selected = option;
    isOpen = false;
  }
</script>

<div class="relative">
  <button onclick={() => isOpen = !isOpen}>
    {selected || 'Select an option'}
  </button>

  {#if isOpen}
    <div class="absolute mt-1 w-full bg-white border rounded shadow-lg">
      {#each options as option}
        <button
          onclick={() => select(option)}
          class="w-full p-2 text-left hover:bg-gray-100"
        >
          {option}
        </button>
      {/each}
    </div>
  {/if}
</div>
```

## Vanilla JS Alternative Examples

Before using Svelte, consider if vanilla JS is sufficient:

### Toggle (Vanilla JS)

```astro
<!-- Instead of a Svelte component -->
<button id="menu-toggle">Menu</button>
<nav id="menu" class="hidden">
  <a href="/">Home</a>
  <a href="/about">About</a>
</nav>

<script>
  document.getElementById('menu-toggle')?.addEventListener('click', () => {
    document.getElementById('menu')?.classList.toggle('hidden');
  });
</script>
```

### Simple Counter (Vanilla JS)

```astro
<button id="decrement">-</button>
<span id="count">0</span>
<button id="increment">+</button>

<script>
  let count = 0;
  const display = document.getElementById('count');

  document.getElementById('decrement')?.addEventListener('click', () => {
    count--;
    display!.textContent = String(count);
  });

  document.getElementById('increment')?.addEventListener('click', () => {
    count++;
    display!.textContent = String(count);
  });
</script>
```

**Use Svelte when:**
- State becomes complex (nested objects, arrays)
- You need reactive derived values
- Multiple components need shared state
- Form handling with validation

## Best Practices

### 1. Choose the Right Hydration Strategy

- `client:load` - Critical, above-fold interactions
- `client:idle` - Non-critical UI elements
- `client:visible` - Below-fold content
- `client:media` - Responsive components
- `client:only` - Browser-dependent features

### 2. Minimize Client JavaScript

Use Svelte only where interactivity is truly needed. Static content should be plain Astro components.

### 3. TypeScript Props

Always type component props:

```svelte
<script lang="ts">
  interface Props {
    title: string;
    count?: number;
    onUpdate?: (value: number) => void;
  }

  let { title, count = 0, onUpdate }: Props = $props();
</script>
```

### 4. Keep Components Small

Extract logic to separate files:

```ts
// src/lib/api.ts
export async function fetchUser(id: string) {
  const res = await fetch(`/api/users/${id}`);
  return res.json();
}
```

```svelte
<script lang="ts">
  import { fetchUser } from '../lib/api';

  let user = $state(null);

  $effect(() => {
    fetchUser('123').then(data => user = data);
  });
</script>
```

### 5. Use Stores for Shared State

For state shared across components, use Svelte stores instead of prop drilling.

## Resources

- [Astro + Svelte Docs](https://docs.astro.build/en/guides/integrations-guide/svelte/)
- [Svelte Documentation](https://svelte.dev/docs)
- [Svelte 5 Runes](https://svelte.dev/docs/svelte/what-are-runes)

## Troubleshooting

**Issue: Hydration mismatch**
- Ensure server and client render the same content
- Avoid browser-only APIs in initial render
- Use `client:only` if SSR not possible

**Issue: Component not interactive**
- Add a client directive (`client:load`, etc.)
- Check browser console for hydration errors

**Issue: Store not reactive**
- Use `$store` syntax to subscribe
- Ensure store is imported correctly

**Issue: TypeScript errors**
- Use `lang="ts"` in script tags
- Define proper Props interface
