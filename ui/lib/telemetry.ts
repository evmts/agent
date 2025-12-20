/**
 * Frontend Telemetry Module
 *
 * Captures and reports:
 * - JavaScript errors (uncaught exceptions, unhandled rejections)
 * - Performance metrics (page load, navigation timing)
 * - User interactions (for debugging flow issues)
 * - Network errors (failed API calls)
 */

// Types
interface TelemetryEvent {
  type: 'error' | 'performance' | 'interaction' | 'network';
  timestamp: string;
  sessionId: string;
  data: Record<string, unknown>;
}

interface ErrorData {
  message: string;
  stack?: string;
  source?: string;
  lineno?: number;
  colno?: number;
  componentStack?: string;
}

interface PerformanceData {
  metric: string;
  value: number;
  unit: string;
}

interface NetworkData {
  url: string;
  method: string;
  status?: number;
  duration?: number;
  error?: string;
}

// Session ID for correlating events
const sessionId = crypto.randomUUID();

// Event queue for batching
let eventQueue: TelemetryEvent[] = [];
let flushTimeout: ReturnType<typeof setTimeout> | null = null;

// Configuration
const config = {
  endpoint: '/api/telemetry',
  batchSize: 10,
  flushInterval: 5000, // 5 seconds
  enabled: true,
  debug: typeof window !== 'undefined' && window.location.hostname === 'localhost',
};

/**
 * Log a telemetry event
 */
function logEvent(type: TelemetryEvent['type'], data: Record<string, unknown>) {
  if (!config.enabled) return;

  const event: TelemetryEvent = {
    type,
    timestamp: new Date().toISOString(),
    sessionId,
    data,
  };

  if (config.debug) {
    console.log('[Telemetry]', event);
  }

  eventQueue.push(event);

  // Flush if batch size reached
  if (eventQueue.length >= config.batchSize) {
    flush();
  } else if (!flushTimeout) {
    // Schedule flush
    flushTimeout = setTimeout(flush, config.flushInterval);
  }
}

/**
 * Flush queued events to the server
 */
async function flush() {
  if (flushTimeout) {
    clearTimeout(flushTimeout);
    flushTimeout = null;
  }

  if (eventQueue.length === 0) return;

  const events = eventQueue;
  eventQueue = [];

  try {
    // Use sendBeacon for reliability (works even during page unload)
    if (navigator.sendBeacon) {
      navigator.sendBeacon(
        config.endpoint,
        JSON.stringify(events)
      );
    } else {
      await fetch(config.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(events),
        keepalive: true,
      });
    }
  } catch (error) {
    // Re-queue events on failure (up to a limit)
    if (events.length < 100) {
      eventQueue = [...events, ...eventQueue];
    }
    if (config.debug) {
      console.error('[Telemetry] Flush failed:', error);
    }
  }
}

/**
 * Log a JavaScript error
 */
export function logError(error: Error | ErrorEvent | PromiseRejectionEvent, context?: Record<string, unknown>) {
  let errorData: ErrorData;

  if (error instanceof Error) {
    errorData = {
      message: error.message,
      stack: error.stack,
    };
  } else if ('error' in error && error.error instanceof Error) {
    errorData = {
      message: error.error.message,
      stack: error.error.stack,
      source: 'filename' in error ? (error as ErrorEvent).filename : undefined,
      lineno: 'lineno' in error ? (error as ErrorEvent).lineno : undefined,
      colno: 'colno' in error ? (error as ErrorEvent).colno : undefined,
    };
  } else if ('reason' in error) {
    // PromiseRejectionEvent
    const reason = error.reason;
    errorData = {
      message: reason instanceof Error ? reason.message : String(reason),
      stack: reason instanceof Error ? reason.stack : undefined,
    };
  } else {
    errorData = {
      message: String(error),
    };
  }

  logEvent('error', {
    ...errorData,
    url: typeof window !== 'undefined' ? window.location.href : undefined,
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : undefined,
    ...context,
  });
}

/**
 * Log a performance metric
 */
export function logPerformance(metric: string, value: number, unit = 'ms') {
  logEvent('performance', { metric, value, unit } as PerformanceData);
}

/**
 * Log a user interaction
 */
export function logInteraction(action: string, target: string, metadata?: Record<string, unknown>) {
  logEvent('interaction', {
    action,
    target,
    url: typeof window !== 'undefined' ? window.location.href : undefined,
    ...metadata,
  });
}

/**
 * Log a network request/response
 */
export function logNetwork(data: NetworkData) {
  logEvent('network', data);
}

/**
 * Create a wrapped fetch that logs network metrics
 */
export function createTrackedFetch(originalFetch: typeof fetch): typeof fetch {
  return async function trackedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const url = input instanceof Request ? input.url : String(input);
    const method = init?.method || (input instanceof Request ? input.method : 'GET');
    const startTime = performance.now();

    try {
      const response = await originalFetch(input, init);
      const duration = performance.now() - startTime;

      logNetwork({
        url,
        method,
        status: response.status,
        duration,
      });

      // Log 4xx/5xx as errors
      if (response.status >= 400) {
        logError(new Error(`HTTP ${response.status}: ${url}`), {
          networkError: true,
          status: response.status,
          method,
        });
      }

      return response;
    } catch (error) {
      const duration = performance.now() - startTime;

      logNetwork({
        url,
        method,
        duration,
        error: error instanceof Error ? error.message : String(error),
      });

      logError(error instanceof Error ? error : new Error(String(error)), {
        networkError: true,
        method,
        url,
      });

      throw error;
    }
  };
}

/**
 * Wrap an async function with timeout and error tracking
 */
export function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  operationName: string
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      const error = new Error(`Operation "${operationName}" timed out after ${timeoutMs}ms`);
      logError(error, { timeout: true, operationName, timeoutMs });
      reject(error);
    }, timeoutMs);

    promise
      .then((result) => {
        clearTimeout(timeoutId);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        logError(error, { operationName });
        reject(error);
      });
  });
}

/**
 * Initialize global error handlers
 */
export function initTelemetry() {
  if (typeof window === 'undefined') return;

  // Capture uncaught errors
  window.addEventListener('error', (event) => {
    logError(event);
  });

  // Capture unhandled promise rejections
  window.addEventListener('unhandledrejection', (event) => {
    logError(event);
  });

  // Log performance metrics on page load
  window.addEventListener('load', () => {
    const timing = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
    if (timing) {
      logPerformance('domContentLoaded', timing.domContentLoadedEventEnd - timing.startTime);
      logPerformance('pageLoad', timing.loadEventEnd - timing.startTime);
      logPerformance('domInteractive', timing.domInteractive - timing.startTime);
      logPerformance('ttfb', timing.responseStart - timing.requestStart);
    }
  });

  // Flush events before page unload
  window.addEventListener('beforeunload', () => {
    flush();
  });

  // Log page visibility changes (useful for debugging stuck states)
  document.addEventListener('visibilitychange', () => {
    logInteraction('visibilitychange', 'document', {
      visibilityState: document.visibilityState,
    });
  });

  if (config.debug) {
    console.log('[Telemetry] Initialized with session:', sessionId);
  }
}

// Export session ID for correlation
export { sessionId };
