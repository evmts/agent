import { SignJWT, jwtVerify, type JWTPayload as JoseJWTPayload } from 'jose';

const JWT_EXPIRY = '7d'; // 7 days
const COOKIE_NAME = 'plue_token';

export interface JWTPayload extends JoseJWTPayload {
  userId: number;
  username: string;
  isAdmin: boolean;
}

function getSecret(): Uint8Array {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET environment variable is not set');
  }
  return new TextEncoder().encode(secret);
}

export async function signJWT(payload: Omit<JWTPayload, 'exp' | 'iat'>): Promise<string> {
  const jwt = await new SignJWT(payload)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(JWT_EXPIRY)
    .sign(getSecret());

  return jwt;
}

export async function verifyJWT(token: string): Promise<JWTPayload | null> {
  try {
    const { payload } = await jwtVerify(token, getSecret());
    return payload as JWTPayload;
  } catch {
    return null;
  }
}

export function setJWTCookie(headers: Headers, token: string): void {
  const maxAge = 7 * 24 * 60 * 60; // 7 days in seconds
  const cookie = `${COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}`;
  headers.append('Set-Cookie', cookie);
}

export function clearJWTCookie(headers: Headers): void {
  const cookie = `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
  headers.append('Set-Cookie', cookie);
}

export function getJWTFromCookie(cookieHeader: string | null): string | null {
  if (!cookieHeader) return null;
  const match = cookieHeader.match(new RegExp(`${COOKIE_NAME}=([^;]+)`));
  return match ? match[1] : null;
}
