/**
 * Analytics event tracking for Edge Worker
 *
 * Tracks events using Cloudflare Workers Analytics Engine.
 * Falls back gracefully if Analytics binding is not available.
 */

import type { Env } from '../types';

// Event types for tracking
export type EventType =
  | 'request'
  | 'auth_success'
  | 'auth_failure'
  | 'rate_limited'
  | 'cache_hit'
  | 'cache_miss'
  | 'cache_bypass'
  | 'cache_stale'
  | 'error';

export type CacheStatus = 'HIT' | 'MISS' | 'BYPASS' | 'STALE';

export interface AnalyticsEvent {
  type: EventType;
  path: string;
  method: string;
  status: number;
  duration_ms: number;
  cache_status?: CacheStatus;
  user_address_prefix?: string;  // First 10 chars for privacy
  error_type?: string;
  country?: string;
  colo?: string;  // Cloudflare colo (data center)
}

export class Analytics {
  private env: Env;
  private events: AnalyticsEvent[] = [];

  constructor(env: Env) {
    this.env = env;
  }

  track(event: AnalyticsEvent): void {
    this.events.push(event);
  }

  /**
   * Flush events to Workers Analytics Engine
   * Uses waitUntil to not block response
   */
  async flush(ctx: ExecutionContext): Promise<void> {
    if (this.events.length === 0) {
      return;
    }

    // Use waitUntil to not block response
    ctx.waitUntil(
      Promise.all(this.events.map(event => this.writeDataPoint(event)))
    );
  }

  private async writeDataPoint(event: AnalyticsEvent): Promise<void> {
    // Check if Analytics Engine binding exists
    if (!('ANALYTICS' in this.env)) {
      return;
    }

    const analytics = this.env.ANALYTICS as AnalyticsEngineDataset;

    // Workers Analytics Engine format
    // Blobs: string data (max 20)
    // Doubles: numeric data (max 20)
    // Indexes: indexed fields for querying (max 1)
    analytics.writeDataPoint({
      blobs: [
        event.type,
        event.path,
        event.method,
        event.cache_status || '',
        event.user_address_prefix || '',
        event.error_type || '',
        event.country || '',
        event.colo || '',
      ],
      doubles: [
        event.status,
        event.duration_ms,
      ],
      indexes: [event.type],  // Primary index for querying
    });
  }
}

/**
 * Extract analytics event from request/response
 */
export function createAnalyticsEvent(
  request: Request,
  response: Response,
  duration_ms: number,
  options: {
    type?: EventType;
    userAddressPrefix?: string;
    errorType?: string;
  } = {}
): AnalyticsEvent {
  const url = new URL(request.url);
  const cacheStatus = response.headers.get('X-Cache') as CacheStatus | null;

  // Determine event type from cache status if not provided
  let type = options.type || 'request';
  if (!options.type && cacheStatus) {
    switch (cacheStatus) {
      case 'HIT':
        type = 'cache_hit';
        break;
      case 'MISS':
        type = 'cache_miss';
        break;
      case 'BYPASS':
        type = 'cache_bypass';
        break;
      case 'STALE':
        type = 'cache_stale';
        break;
    }
  }

  return {
    type,
    path: url.pathname,
    method: request.method,
    status: response.status,
    duration_ms,
    cache_status: cacheStatus || undefined,
    user_address_prefix: options.userAddressPrefix,
    error_type: options.errorType,
    country: request.headers.get('CF-IPCountry') || undefined,
    colo: (request.cf as { colo?: string } | undefined)?.colo,
  };
}
