/**
 * Structured logging for Edge Worker
 *
 * Outputs JSON logs for Cloudflare's log collection.
 * Each request gets a unique ID for tracing.
 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogContext {
  requestId: string;
  clientIP: string;
  path: string;
  method: string;
  userAddress?: string;
  [key: string]: unknown;
}

interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: string;
  context: LogContext;
  duration_ms: number;
  error?: string;
  stack?: string;
}

export class Logger {
  private context: LogContext;
  private startTime: number;

  constructor(request: Request) {
    this.startTime = Date.now();
    // Use existing X-Request-ID if present, otherwise generate new one
    const existingRequestId = request.headers.get('X-Request-ID');
    this.context = {
      requestId: existingRequestId || crypto.randomUUID(),
      clientIP: request.headers.get('CF-Connecting-IP') || 'unknown',
      path: new URL(request.url).pathname,
      method: request.method,
    };
  }

  setUserAddress(address: string): void {
    this.context.userAddress = address;
  }

  addContext(key: string, value: unknown): void {
    this.context[key] = value;
  }

  private log(level: LogLevel, message: string, extra?: Record<string, unknown>): void {
    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date().toISOString(),
      context: { ...this.context, ...extra },
      duration_ms: Date.now() - this.startTime,
    };

    // Use console methods for Cloudflare log collection
    const output = JSON.stringify(entry);
    switch (level) {
      case 'debug':
        console.debug(output);
        break;
      case 'info':
        console.info(output);
        break;
      case 'warn':
        console.warn(output);
        break;
      case 'error':
        console.error(output);
        break;
    }
  }

  debug(message: string, extra?: Record<string, unknown>): void {
    this.log('debug', message, extra);
  }

  info(message: string, extra?: Record<string, unknown>): void {
    this.log('info', message, extra);
  }

  warn(message: string, extra?: Record<string, unknown>): void {
    this.log('warn', message, extra);
  }

  error(message: string, error?: Error, extra?: Record<string, unknown>): void {
    this.log('error', message, {
      ...extra,
      error: error?.message,
      stack: error?.stack,
    });
  }

  getRequestId(): string {
    return this.context.requestId;
  }

  getDuration(): number {
    return Date.now() - this.startTime;
  }

  getContext(): LogContext {
    return { ...this.context };
  }
}
