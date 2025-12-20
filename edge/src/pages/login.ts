import type { Env, JWTPayload } from '../types';
import { layout } from '../templates/layout';
import { htmlResponse } from '../lib/html';

export async function handleLogin(
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
  const redirect = url.searchParams.get('redirect') || '/';

  const content = renderLoginPage(error, redirect);
  return htmlResponse(layout({ title: 'Login', user: null }, content));
}

function renderLoginPage(error: string | null, redirect: string): string {
  return `
    <div style="max-width: 400px; margin: 2rem auto;">
      <h1 class="mb-4">Login</h1>

      ${error ? `<div class="card mb-4" style="border-color: #ef4444; color: #ef4444;">${error}</div>` : ''}

      <form action="/api/auth/login" method="POST" class="card">
        <input type="hidden" name="redirect" value="${redirect}">

        <div class="mb-4">
          <label for="usernameOrEmail" style="display:block;margin-bottom:0.25rem;">Username or Email</label>
          <input type="text" id="usernameOrEmail" name="usernameOrEmail" required
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <div class="mb-4">
          <label for="password" style="display:block;margin-bottom:0.25rem;">Password</label>
          <input type="password" id="password" name="password" required
                 style="width:100%;padding:0.5rem;border:2px solid var(--border);font-family:inherit;">
        </div>

        <button type="submit" class="btn btn-primary" style="width:100%;">Login</button>
      </form>

      <p class="text-muted mt-4" style="text-align:center;">
        Don't have an account? <a href="/register">Register</a>
      </p>

      <p class="text-muted" style="text-align:center;">
        <a href="/password/reset">Forgot password?</a>
      </p>
    </div>
  `;
}
