/**
 * MetricsDO - Durable Object for aggregating metrics
 *
 * Collects metrics across all edge worker instances.
 * Provides Prometheus-compatible endpoint for scraping.
 */

export interface MetricsBucket {
  requests_total: number;
  requests_by_status: Record<number, number>;
  auth_success_total: number;
  auth_failure_total: number;
  rate_limited_total: number;
  cache_hits_total: number;
  cache_misses_total: number;
  cache_bypasses_total: number;
  cache_stales_total: number;
  errors_total: number;
  request_duration_sum: number;
  request_duration_count: number;
  // Histogram buckets for latency distribution
  request_duration_buckets: Record<string, number>;
}

export interface IncrementPayload {
  type: 'auth_success' | 'auth_failure' | 'rate_limited' | 'cache_hit' | 'cache_miss' | 'cache_bypass' | 'cache_stale' | 'error' | 'request';
  status?: number;
  duration_ms?: number;
}

// Histogram buckets in ms (matches Prometheus standard)
const DURATION_BUCKETS = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000];

function getDefaultMetrics(): MetricsBucket {
  const buckets: Record<string, number> = {};
  for (const bucket of DURATION_BUCKETS) {
    buckets[bucket.toString()] = 0;
  }
  buckets['+Inf'] = 0;

  return {
    requests_total: 0,
    requests_by_status: {},
    auth_success_total: 0,
    auth_failure_total: 0,
    rate_limited_total: 0,
    cache_hits_total: 0,
    cache_misses_total: 0,
    cache_bypasses_total: 0,
    cache_stales_total: 0,
    errors_total: 0,
    request_duration_sum: 0,
    request_duration_count: 0,
    request_duration_buckets: buckets,
  };
}

export class MetricsDO implements DurableObject {
  private state: DurableObjectState;
  private metrics: MetricsBucket;
  private dirty: boolean = false;

  constructor(state: DurableObjectState) {
    this.state = state;
    this.metrics = getDefaultMetrics();

    // Load persisted metrics on startup
    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<MetricsBucket>('metrics');
      if (stored) {
        // Merge with defaults to handle schema changes
        this.metrics = { ...getDefaultMetrics(), ...stored };
      }
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // GET /metrics - Return current metrics
    if (url.pathname === '/metrics' && request.method === 'GET') {
      return new Response(JSON.stringify(this.metrics), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // POST /increment - Increment counters
    if (url.pathname === '/increment' && request.method === 'POST') {
      const body = await request.json() as IncrementPayload;
      this.incrementMetrics(body);
      return new Response('OK', { status: 200 });
    }

    // POST /reset - Reset all metrics (for testing)
    if (url.pathname === '/reset' && request.method === 'POST') {
      this.metrics = getDefaultMetrics();
      await this.state.storage.put('metrics', this.metrics);
      return new Response('OK', { status: 200 });
    }

    return new Response('Not Found', { status: 404 });
  }

  private incrementMetrics(payload: IncrementPayload): void {
    this.metrics.requests_total++;

    // Track by status code
    if (payload.status) {
      this.metrics.requests_by_status[payload.status] =
        (this.metrics.requests_by_status[payload.status] || 0) + 1;
    }

    // Track duration
    if (payload.duration_ms !== undefined) {
      this.metrics.request_duration_sum += payload.duration_ms;
      this.metrics.request_duration_count++;

      // Update histogram buckets
      for (const bucket of DURATION_BUCKETS) {
        if (payload.duration_ms <= bucket) {
          this.metrics.request_duration_buckets[bucket.toString()]++;
        }
      }
      this.metrics.request_duration_buckets['+Inf']++;
    }

    // Increment type-specific counter
    switch (payload.type) {
      case 'auth_success':
        this.metrics.auth_success_total++;
        break;
      case 'auth_failure':
        this.metrics.auth_failure_total++;
        break;
      case 'rate_limited':
        this.metrics.rate_limited_total++;
        break;
      case 'cache_hit':
        this.metrics.cache_hits_total++;
        break;
      case 'cache_miss':
        this.metrics.cache_misses_total++;
        break;
      case 'cache_bypass':
        this.metrics.cache_bypasses_total++;
        break;
      case 'cache_stale':
        this.metrics.cache_stales_total++;
        break;
      case 'error':
        this.metrics.errors_total++;
        break;
    }

    this.dirty = true;

    // Persist every 100 requests to reduce writes
    if (this.metrics.requests_total % 100 === 0) {
      this.persistMetrics();
    }
  }

  private async persistMetrics(): Promise<void> {
    if (this.dirty) {
      await this.state.storage.put('metrics', this.metrics);
      this.dirty = false;
    }
  }
}
