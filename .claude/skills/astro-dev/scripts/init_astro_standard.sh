#!/bin/bash
# Initialize standard Astro project (no deployment platform)
# Usage: ./init_astro_standard.sh <project-name>

set -e

PROJECT_NAME="${1:-my-astro-site}"

echo "Creating standard Astro project..."
echo "Project name: $PROJECT_NAME"
echo ""

# Create Astro project
npm create astro@latest "$PROJECT_NAME" -- \
  --template=minimal \
  --install \
  --no-git \
  --typescript=strict

cd "$PROJECT_NAME"

echo ""
echo "Installing Svelte and Tailwind..."

# Install Svelte (use sparingly - prefer vanilla JS)
npm install svelte

# Install Tailwind CSS v4
npm install -D tailwindcss @tailwindcss/vite

# Add Astro integrations
npx astro add svelte --yes

echo ""
echo "Setting up Tailwind CSS v4..."

# Create global CSS
mkdir -p src/styles
cat > src/styles/global.css << 'EOF'
@import "tailwindcss";

@plugin "@tailwindcss/typography";
@plugin "@tailwindcss/forms";

@custom-variant dark (&:where(.dark, .dark *));

@theme {
  --font-sans: system-ui, sans-serif;
}
EOF

# Update astro.config.mjs
cat > astro.config.mjs << 'EOF'
import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  output: 'static',
  integrations: [svelte()],
  vite: {
    plugins: [tailwindcss()],
  },
});
EOF

# Create a simple layout
mkdir -p src/layouts
cat > src/layouts/Layout.astro << 'EOF'
---
import '../styles/global.css';

interface Props {
  title: string;
}

const { title } = Astro.props;
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width" />
    <meta name="generator" content={Astro.generator} />
    <title>{title}</title>
  </head>
  <body class="bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100">
    <slot />
  </body>
</html>
EOF

# Update index page
cat > src/pages/index.astro << 'EOF'
---
import Layout from '../layouts/Layout.astro';
---

<Layout title="Welcome to Astro">
  <main class="container mx-auto px-4 py-12">
    <h1 class="text-4xl font-bold mb-4">
      Welcome to <span class="text-blue-600">Astro</span>
    </h1>
    <p class="text-lg text-gray-600 dark:text-gray-400 mb-8">
      Start building your amazing site!
    </p>

    <!-- Example: Vanilla JS for simple interactions -->
    <button id="toggle-btn" class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700">
      Toggle Message
    </button>
    <p id="message" class="mt-4 hidden">
      Hello! This toggle uses vanilla JS - no framework needed.
    </p>
  </main>

  <script>
    // Prefer vanilla JS for simple interactions
    document.getElementById('toggle-btn')?.addEventListener('click', () => {
      document.getElementById('message')?.classList.toggle('hidden');
    });
  </script>
</Layout>
EOF

# Create islands directory for Svelte components (when needed)
mkdir -p src/islands

echo ""
echo "Project setup complete!"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_NAME"
echo "  npm run dev    # Start development server"
echo "  npm run build  # Build for production"
echo ""
echo "Remember: Prefer vanilla JS in <script> tags for simple interactions."
echo "Only use Svelte islands in src/islands/ when you need reactive state."
