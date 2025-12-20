import type { APIRoute } from 'astro';

/**
 * Telemetry endpoint for receiving client-side events.
 *
 * Events are logged to console for Loki collection and can be
 * forwarded to external services (e.g., Sentry, PostHog) if configured.
 */

interface TelemetryEvent {
  type: 'error' | 'performance' | 'interaction' | 'network';
  timestamp: string;
  sessionId: string;
  data: Record<string, unknown>;
}

// Structured log format for Loki/Promtail
function structuredLog(level: string, event: TelemetryEvent) {
  const logEntry = {
    level,
    service: 'plue-web',
    type: event.type,
    sessionId: event.sessionId,
    timestamp: event.timestamp,
    ...event.data,
  };
  console.log(JSON.stringify(logEntry));
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const events = await request.json() as TelemetryEvent[];

    if (!Array.isArray(events)) {
      return new Response(JSON.stringify({ error: 'Expected array of events' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Process each event
    for (const event of events) {
      if (!event.type || !event.sessionId) {
        continue; // Skip malformed events
      }

      switch (event.type) {
        case 'error':
          structuredLog('error', event);
          break;
        case 'network':
          // Log network errors at error level, successful requests at debug
          const level = event.data.error || (event.data.status as number) >= 400 ? 'warn' : 'debug';
          structuredLog(level, event);
          break;
        case 'performance':
          structuredLog('info', event);
          break;
        case 'interaction':
          structuredLog('debug', event);
          break;
        default:
          structuredLog('debug', event);
      }
    }

    return new Response(JSON.stringify({ success: true, processed: events.length }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Telemetry error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
};
