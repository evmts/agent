/**
 * Cloudflare Workers environment bindings.
 */
export interface Env {
  ORIGIN_HOST: string;
  BUILD_VERSION: string;

  // JWT secret for session tokens
  JWT_SECRET: string;

  // Durable Object for auth state (nonces, sessions, blocklist)
  // Provides strong consistency for nonce replay protection
  AUTH_DO: DurableObjectNamespace;

  // Durable Object for rate limiting
  // Provides atomic counters with strong consistency
  RATE_LIMIT_DO: DurableObjectNamespace;

  // Durable Object for metrics aggregation
  // Collects metrics across all edge instances
  METRICS_DO: DurableObjectNamespace;

  // Optional: Cloudflare API credentials for programmatic purge
  CF_ZONE_ID?: string;
  CF_API_TOKEN?: string;

  // Optional: Workers Analytics Engine binding
  ANALYTICS?: AnalyticsEngineDataset;

  // Optional: Secret key for accessing metrics endpoint
  // If set, requests to /metrics must include this in Authorization header
  METRICS_API_KEY?: string;

  // Optional: Allowed CIDRs for metrics endpoint (comma-separated)
  // e.g., "10.0.0.0/8,192.168.0.0/16"
  METRICS_ALLOWED_IPS?: string;
}
