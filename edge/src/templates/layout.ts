import type { JWTPayload } from '../types';
import { renderNav } from '../lib/html';

interface LayoutOptions {
  title: string;
  user: JWTPayload | null;
  navLinks?: Array<{ href: string; label: string; active?: boolean }>;
}

export function layout(options: LayoutOptions, content: string): string {
  const { title, user, navLinks = [] } = options;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} - Plue</title>
  <style>
    :root {
      --bg: #fff;
      --fg: #000;
      --border: #000;
      --muted: #666;
      --accent: #0066cc;
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Mono', 'Droid Sans Mono', monospace;
      font-size: 14px;
      line-height: 1.5;
      background: var(--bg);
      color: var(--fg);
    }

    a {
      color: var(--accent);
      text-decoration: none;
    }

    a:hover {
      text-decoration: underline;
    }

    .main-nav {
      display: flex;
      align-items: center;
      gap: 2rem;
      padding: 1rem 2rem;
      border-bottom: 2px solid var(--border);
    }

    .logo {
      font-weight: bold;
      font-size: 1.5rem;
      color: var(--fg);
    }

    .nav-links {
      display: flex;
      gap: 1.5rem;
      flex: 1;
    }

    .nav-link {
      color: var(--muted);
    }

    .nav-link.active {
      color: var(--fg);
      font-weight: bold;
    }

    .nav-user {
      display: flex;
      gap: 1rem;
      align-items: center;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    .btn {
      display: inline-block;
      padding: 0.5rem 1rem;
      border: 2px solid var(--border);
      background: var(--bg);
      color: var(--fg);
      font-family: inherit;
      font-size: inherit;
      cursor: pointer;
    }

    .btn:hover {
      background: var(--fg);
      color: var(--bg);
    }

    .btn-primary {
      background: var(--fg);
      color: var(--bg);
    }

    .btn-primary:hover {
      background: var(--bg);
      color: var(--fg);
    }

    .btn-link {
      background: none;
      border: none;
      color: var(--accent);
      cursor: pointer;
      font-family: inherit;
      font-size: inherit;
    }

    .card {
      border: 2px solid var(--border);
      padding: 1rem;
      margin-bottom: 1rem;
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 0.5rem;
    }

    .card-title {
      font-weight: bold;
    }

    .card-meta {
      color: var(--muted);
      font-size: 0.875rem;
    }

    .badge {
      display: inline-block;
      padding: 0.125rem 0.5rem;
      border: 1px solid var(--border);
      font-size: 0.75rem;
      text-transform: uppercase;
    }

    .badge-open {
      background: #22c55e;
      color: white;
      border-color: #22c55e;
    }

    .badge-closed {
      background: #ef4444;
      color: white;
      border-color: #ef4444;
    }

    .badge-merged {
      background: #8b5cf6;
      color: white;
      border-color: #8b5cf6;
    }

    .list {
      list-style: none;
    }

    .list-item {
      padding: 1rem;
      border: 2px solid var(--border);
      border-bottom: none;
    }

    .list-item:last-child {
      border-bottom: 2px solid var(--border);
    }

    .list-item-title {
      font-weight: bold;
      margin-bottom: 0.25rem;
    }

    .list-item-meta {
      color: var(--muted);
      font-size: 0.875rem;
    }

    .tabs {
      display: flex;
      gap: 0;
      border-bottom: 2px solid var(--border);
      margin-bottom: 1rem;
    }

    .tab {
      padding: 0.75rem 1.5rem;
      border: 2px solid var(--border);
      border-bottom: none;
      margin-bottom: -2px;
      color: var(--muted);
    }

    .tab.active {
      background: var(--bg);
      color: var(--fg);
      font-weight: bold;
    }

    .empty {
      text-align: center;
      padding: 3rem;
      color: var(--muted);
    }

    h1 { font-size: 2rem; margin-bottom: 1rem; }
    h2 { font-size: 1.5rem; margin-bottom: 0.75rem; }
    h3 { font-size: 1.25rem; margin-bottom: 0.5rem; }

    .flex { display: flex; }
    .items-center { align-items: center; }
    .justify-between { justify-content: space-between; }
    .gap-1 { gap: 0.25rem; }
    .gap-2 { gap: 0.5rem; }
    .gap-4 { gap: 1rem; }
    .mb-2 { margin-bottom: 0.5rem; }
    .mb-4 { margin-bottom: 1rem; }
    .mt-4 { margin-top: 1rem; }
    .text-muted { color: var(--muted); }
  </style>
</head>
<body>
  ${renderNav(user, navLinks)}
  <main class="container">
    ${content}
  </main>
</body>
</html>`;
}
