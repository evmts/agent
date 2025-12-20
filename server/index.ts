/**
 * Server module - Hono app with Bun.serve().
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { authMiddleware } from './middleware/auth';
import authRoutes from './routes/auth';
import usersRoutes from './routes/users';
import sshKeysRoutes from './routes/ssh-keys';
import tokensRoutes from './routes/tokens';
// JJ-native routes (replaces git-based branches, pulls)
import bookmarkRoutes from './routes/bookmarks';
import changesRoutes from './routes/changes';
import operationsRoutes from './routes/operations';
import landingRoutes from './routes/landing';
import routes from './routes';

export { ServerEventBus, getServerEventBus, setServerEventBus } from './event-bus';

// Create Hono app
const app = new Hono();

// ElectricSQL configuration
const ELECTRIC_URL = process.env.ELECTRIC_URL || 'http://localhost:3000';

// CORS configuration - use environment variable for allowed origins
const ALLOWED_ORIGINS = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(o => o.trim())
  : ['http://localhost:4321', 'http://localhost:4000', 'http://localhost:3000'];

// Middleware
app.use('*', logger());
app.use('*', cors({
  origin: (origin) => {
    // Allow requests with no origin (like mobile apps or curl)
    if (!origin) return null;
    // Check if origin is in allowed list
    if (ALLOWED_ORIGINS.includes(origin)) {
      return origin;
    }
    // In development, allow localhost with any port
    if (process.env.NODE_ENV !== 'production' && origin.startsWith('http://localhost:')) {
      return origin;
    }
    return null;
  },
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowHeaders: ['Content-Type', 'Authorization'],
  exposeHeaders: [
    'electric-offset',
    'electric-handle',
    'electric-schema',
    'electric-cursor',
    'electric-up-to-date',
  ],
  maxAge: 600,
  credentials: true,
}));

// Apply auth middleware globally (before routes)
app.use('*', authMiddleware);

// ElectricSQL Shape API proxy
// This endpoint proxies shape requests to Electric for real-time sync
app.get('/shape', async (c) => {
  const url = new URL(c.req.url);
  const originUrl = new URL(`${ELECTRIC_URL}/v1/shape`);

  // Forward query parameters to Electric
  url.searchParams.forEach((value, key) => {
    originUrl.searchParams.set(key, value);
  });

  // Proxy the request to Electric using fetch
  const response = await fetch(originUrl.toString(), {
    method: c.req.method,
    headers: c.req.raw.headers,
  });

  // Return the response with all Electric headers
  return new Response(response.body, {
    status: response.status,
    headers: response.headers,
  });
});

// Mount API routes under /api prefix
app.route('/api/auth', authRoutes);
app.route('/api/users', usersRoutes);
app.route('/api/ssh-keys', sshKeysRoutes);
app.route('/api/user/tokens', tokensRoutes);

// Mount JJ-native API routes (replaces git-based branches/pulls)
app.route('/api', bookmarkRoutes);
app.route('/api', changesRoutes);
app.route('/api', operationsRoutes);
app.route('/api', landingRoutes);

// Mount existing routes
app.route('/', routes);

// Standard error response type
interface ErrorResponse {
  error: string;
  code?: string;
  details?: string;
}

// Error handling - don't expose internal details in production
app.onError((err, c) => {
  console.error('Server error:', err);

  const isProduction = process.env.NODE_ENV === 'production';

  // Determine error code from error name
  const errorCode = err.name === 'ValidationError' ? 'VALIDATION_ERROR'
    : err.name === 'UnauthorizedError' ? 'UNAUTHORIZED'
    : err.name === 'NotFoundError' ? 'NOT_FOUND'
    : 'INTERNAL_ERROR';

  const response: ErrorResponse = {
    error: isProduction ? 'An unexpected error occurred' : err.message,
    code: errorCode,
  };

  // Only include details in development
  if (!isProduction && err.stack) {
    response.details = err.stack;
  }

  // Return appropriate status code
  const status = err.name === 'ValidationError' ? 400
    : err.name === 'UnauthorizedError' ? 401
    : err.name === 'NotFoundError' ? 404
    : 500;

  return c.json(response, status);
});

// 404 handler
app.notFound((c) => {
  return c.json({ error: 'Not found' }, 404);
});

export { app };
export default app;