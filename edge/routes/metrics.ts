/**
 * Prometheus-compatible metrics endpoint
 *
 * Exposes metrics in Prometheus text format for scraping.
 * Can be used with Prometheus, Grafana, or viewed directly.
 */

import type { Env } from '../types';
import type { MetricsBucket } from '../metrics-do';

// Histogram buckets (must match metrics-do.ts)
const DURATION_BUCKETS = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000];

/**
 * Handle GET /metrics
 * Returns Prometheus-compatible metrics text
 */
export async function handleMetrics(request: Request, env: Env): Promise<Response> {
  // Check if METRICS_DO binding exists
  if (!('METRICS_DO' in env)) {
    return new Response('Metrics not configured', { status: 503 });
  }

  try {
    // Get metrics from Durable Object
    const metricsId = env.METRICS_DO.idFromName('global');
    const metricsDO = env.METRICS_DO.get(metricsId);

    const response = await metricsDO.fetch(new Request('https://do/metrics'));
    if (!response.ok) {
      throw new Error(`Failed to fetch metrics: ${response.status}`);
    }

    const metrics: MetricsBucket = await response.json();

    // Format as Prometheus text exposition format
    const lines = formatPrometheusMetrics(metrics);

    return new Response(lines.join('\n'), {
      headers: {
        'Content-Type': 'text/plain; version=0.0.4; charset=utf-8',
        'Cache-Control': 'no-cache',
      },
    });
  } catch (error) {
    console.error('Failed to get metrics:', error);
    return new Response('Failed to get metrics', { status: 500 });
  }
}

function formatPrometheusMetrics(metrics: MetricsBucket): string[] {
  const lines: string[] = [];

  // Request totals
  lines.push('# HELP plue_edge_requests_total Total number of requests');
  lines.push('# TYPE plue_edge_requests_total counter');
  lines.push(`plue_edge_requests_total ${metrics.requests_total}`);
  lines.push('');

  // Requests by status
  lines.push('# HELP plue_edge_requests_by_status Requests by HTTP status code');
  lines.push('# TYPE plue_edge_requests_by_status counter');
  for (const [status, count] of Object.entries(metrics.requests_by_status)) {
    lines.push(`plue_edge_requests_by_status{status="${status}"} ${count}`);
  }
  lines.push('');

  // Auth metrics
  lines.push('# HELP plue_edge_auth_success_total Successful authentications');
  lines.push('# TYPE plue_edge_auth_success_total counter');
  lines.push(`plue_edge_auth_success_total ${metrics.auth_success_total}`);
  lines.push('');

  lines.push('# HELP plue_edge_auth_failure_total Failed authentications');
  lines.push('# TYPE plue_edge_auth_failure_total counter');
  lines.push(`plue_edge_auth_failure_total ${metrics.auth_failure_total}`);
  lines.push('');

  // Rate limiting
  lines.push('# HELP plue_edge_rate_limited_total Rate limited requests');
  lines.push('# TYPE plue_edge_rate_limited_total counter');
  lines.push(`plue_edge_rate_limited_total ${metrics.rate_limited_total}`);
  lines.push('');

  // Cache metrics
  lines.push('# HELP plue_edge_cache_hits_total Cache hits');
  lines.push('# TYPE plue_edge_cache_hits_total counter');
  lines.push(`plue_edge_cache_hits_total ${metrics.cache_hits_total}`);
  lines.push('');

  lines.push('# HELP plue_edge_cache_misses_total Cache misses');
  lines.push('# TYPE plue_edge_cache_misses_total counter');
  lines.push(`plue_edge_cache_misses_total ${metrics.cache_misses_total}`);
  lines.push('');

  lines.push('# HELP plue_edge_cache_bypasses_total Cache bypasses (authenticated users)');
  lines.push('# TYPE plue_edge_cache_bypasses_total counter');
  lines.push(`plue_edge_cache_bypasses_total ${metrics.cache_bypasses_total}`);
  lines.push('');

  lines.push('# HELP plue_edge_cache_stales_total Stale cache serves (origin failures)');
  lines.push('# TYPE plue_edge_cache_stales_total counter');
  lines.push(`plue_edge_cache_stales_total ${metrics.cache_stales_total}`);
  lines.push('');

  // Errors
  lines.push('# HELP plue_edge_errors_total Total errors');
  lines.push('# TYPE plue_edge_errors_total counter');
  lines.push(`plue_edge_errors_total ${metrics.errors_total}`);
  lines.push('');

  // Duration histogram
  lines.push('# HELP plue_edge_request_duration_ms Request duration in milliseconds');
  lines.push('# TYPE plue_edge_request_duration_ms histogram');

  // Cumulative histogram buckets
  let cumulative = 0;
  for (const bucket of DURATION_BUCKETS) {
    cumulative += metrics.request_duration_buckets[bucket.toString()] || 0;
    lines.push(`plue_edge_request_duration_ms_bucket{le="${bucket}"} ${cumulative}`);
  }
  cumulative += metrics.request_duration_buckets['+Inf'] || 0;
  lines.push(`plue_edge_request_duration_ms_bucket{le="+Inf"} ${metrics.request_duration_count}`);
  lines.push(`plue_edge_request_duration_ms_sum ${metrics.request_duration_sum}`);
  lines.push(`plue_edge_request_duration_ms_count ${metrics.request_duration_count}`);
  lines.push('');

  // Computed metrics (for convenience)
  const totalCache = metrics.cache_hits_total + metrics.cache_misses_total;
  const cacheHitRate = totalCache > 0 ? (metrics.cache_hits_total / totalCache) : 0;

  lines.push('# HELP plue_edge_cache_hit_rate Cache hit rate (0-1)');
  lines.push('# TYPE plue_edge_cache_hit_rate gauge');
  lines.push(`plue_edge_cache_hit_rate ${cacheHitRate.toFixed(4)}`);
  lines.push('');

  const totalAuth = metrics.auth_success_total + metrics.auth_failure_total;
  const authSuccessRate = totalAuth > 0 ? (metrics.auth_success_total / totalAuth) : 0;

  lines.push('# HELP plue_edge_auth_success_rate Auth success rate (0-1)');
  lines.push('# TYPE plue_edge_auth_success_rate gauge');
  lines.push(`plue_edge_auth_success_rate ${authSuccessRate.toFixed(4)}`);
  lines.push('');

  const avgDuration = metrics.request_duration_count > 0
    ? metrics.request_duration_sum / metrics.request_duration_count
    : 0;

  lines.push('# HELP plue_edge_request_duration_avg_ms Average request duration in ms');
  lines.push('# TYPE plue_edge_request_duration_avg_ms gauge');
  lines.push(`plue_edge_request_duration_avg_ms ${avgDuration.toFixed(2)}`);

  return lines;
}
