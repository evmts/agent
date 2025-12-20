/**
 * Server module - Hono app with Bun.serve().
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { secureHeaders } from 'hono/secure-headers';
import { bodyLimit } from 'hono/body-limit';
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

// Validate critical environment variables at startup
function validateEnvironment() {
  const JWT_SECRET = process.env.JWT_SECRET;
  if (!JWT_SECRET) {
    console.error('FATAL: JWT_SECRET environment variable is not set');
    console.error('Please set JWT_SECRET in your .env file');
    process.exit(1);
  }

  if (JWT_SECRET.length < 32) {
    console.error('WARNING: JWT_SECRET should be at least 32 characters long for security');
  }
}

// Run validation before creating the app
validateEnvironment();

// Create Hono app
const app = new Hono();

// ElectricSQL configuration
const ELECTRIC_URL = process.env.ELECTRIC_URL || 'http://localhost:3000';

// CORS configuration - use environment variable for allowed origins
const ALLOWED_ORIGINS = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(o => o.trim())
  : ['http://localhost:4321', 'http://localhost:4000', 'http://localhost:3000'];

// Middleware (order matters: logger -> security headers -> body limit -> cors -> auth)
app.use('*', logger());

// Security headers middleware
app.use('*', secureHeaders({
  xFrameOptions: 'DENY',
  xContentTypeOptions: 'nosniff',
  xXssProtection: '1; mode=block',
  referrerPolicy: 'strict-origin-when-cross-origin',
  contentSecurityPolicy: {
    defaultSrc: ["'self'"],
    scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
    styleSrc: ["'self'", "'unsafe-inline'"],
    imgSrc: ["'self'", 'data:', 'https:'],
    connectSrc: ["'self'", process.env.ELECTRIC_URL || 'http://localhost:3000'],
    fontSrc: ["'self'", 'data:'],
    objectSrc: ["'none'"],
    mediaSrc: ["'self'"],
    frameSrc: ["'none'"],
  },
  strictTransportSecurity: process.env.NODE_ENV === 'production'
    ? 'max-age=31536000; includeSubDomains; preload'
    : false,
}));

// Request body size limit (10MB)
app.use('*', bodyLimit({
  maxSize: 10 * 1024 * 1024, // 10MB in bytes
  onError: (c) => {
    return c.json({
      error: 'Request body too large',
      code: 'PAYLOAD_TOO_LARGE',
      maxSize: '10MB'
    }, 413);
  },
}));

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