import { jwtVerify } from 'jose';
import type { JWTPayload } from '../types';

const COOKIE_NAME = 'plue_token';

export async function validateSession(
  request: Request,
  jwtSecret: string
): Promise<JWTPayload | null> {
  const cookie = request.headers.get('Cookie');
  if (!cookie) return null;

  const tokenMatch = cookie.match(new RegExp(`${COOKIE_NAME}=([^;]+)`));
  if (!tokenMatch) return null;

  const token = tokenMatch[1];

  try {
    const secret = new TextEncoder().encode(jwtSecret);
    const { payload } = await jwtVerify(token, secret);

    return {
      userId: payload.userId as number,
      username: payload.username as string,
      isAdmin: payload.isAdmin as boolean,
      exp: payload.exp as number,
    };
  } catch {
    return null;
  }
}

export function requireAuth(user: JWTPayload | null, redirectTo = '/login'): Response | null {
  if (!user) {
    return new Response(null, {
      status: 302,
      headers: { Location: redirectTo },
    });
  }
  return null;
}
