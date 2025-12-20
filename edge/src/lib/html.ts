import type { JWTPayload } from '../types';

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

export function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) {
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    if (diffHours === 0) {
      const diffMinutes = Math.floor(diffMs / (1000 * 60));
      return diffMinutes <= 1 ? 'just now' : `${diffMinutes} minutes ago`;
    }
    return diffHours === 1 ? '1 hour ago' : `${diffHours} hours ago`;
  }

  if (diffDays === 1) return 'yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;
  if (diffDays < 30) return `${Math.floor(diffDays / 7)} weeks ago`;
  if (diffDays < 365) return `${Math.floor(diffDays / 30)} months ago`;
  return `${Math.floor(diffDays / 365)} years ago`;
}

export function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-cache',
    },
  });
}

interface NavLink {
  href: string;
  label: string;
  active?: boolean;
}

export function renderNav(user: JWTPayload | null, links: NavLink[] = []): string {
  const navLinks = links
    .map(
      (link) =>
        `<a href="${escapeHtml(link.href)}" class="nav-link${link.active ? ' active' : ''}">${escapeHtml(link.label)}</a>`
    )
    .join('');

  const userSection = user
    ? `<div class="nav-user">
        <a href="/${escapeHtml(user.username)}">${escapeHtml(user.username)}</a>
        <a href="/settings">Settings</a>
        <form action="/api/auth/logout" method="POST" style="display:inline">
          <button type="submit" class="btn-link">Logout</button>
        </form>
      </div>`
    : `<div class="nav-user">
        <a href="/login">Login</a>
        <a href="/register">Register</a>
      </div>`;

  return `<nav class="main-nav">
    <a href="/" class="logo">PLUE</a>
    <div class="nav-links">${navLinks}</div>
    ${userSection}
  </nav>`;
}
