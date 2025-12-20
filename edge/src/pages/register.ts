import type { Env, JWTPayload } from '../types';
import { layout } from '../templates/layout';
import { htmlResponse } from '../lib/html';

export async function handleRegister(
  request: Request,
  env: Env,
  user: JWTPayload | null
): Promise<Response> {
  // If already logged in, redirect to home
  if (user) {
    return new Response(null, {
      status: 302,
      headers: { Location: '/' },
    });
  }

  const url = new URL(request.url);
  const error = url.searchParams.get('error');

  const content = renderRegisterPage(error);
  return htmlResponse(layout({ title: 'Register', user: null }, content));
}

function renderRegisterPage(error: string | null): string {
  return `
    <div style="max-width: 400px; margin: 2rem auto;">
      <h1 class="mb-4">Create Account</h1>

      ${error ? `<div class="card mb-4" style="border-color: #ef4444; color: #ef4444;">${error}</div>` : ''}

      <form action="/api/auth/register" method="POST" class="card">
        <div class="mb-4">
          <label for="username" style="display:block;margin-bottom:0.25rem;">Username</label>
          <input type="text" id="username" name="username" required
                 pattern="[a-zA-Z0-9_-]+"
                 title="Only letters, numbers, underscores and hyphens"
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <div class="mb-4">
          <label for="email" style="display:block;margin-bottom:0.25rem;">Email</label>
          <input type="email" id="email" name="email" required
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <div class="mb-4">
          <label for="displayName" style="display:block;margin-bottom:0.25rem;">Display Name (optional)</label>
          <input type="text" id="displayName" name="displayName"
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <div class="mb-4">
          <label for="password" style="display:block;margin-bottom:0.25rem;">Password</label>
          <input type="password" id="password" name="password" required
                 minlength="8"
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
          <small class="text-muted">Minimum 8 characters</small>
        </div>

        <div class="mb-4">
          <label for="confirmPassword" style="display:block;margin-bottom:0.25rem;">Confirm Password</label>
          <input type="password" id="confirmPassword" name="confirmPassword" required
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <button type="submit" class="btn btn-primary" style="width:100%;">Create Account</button>
      </form>

      <p class="text-muted mt-4" style="text-align:center;">
        Already have an account? <a href="/login">Login</a>
      </p>
    </div>
  `;
}
