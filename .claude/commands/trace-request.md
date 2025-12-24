---
allowed-tools: Bash(curl:*), Bash(docker:*), Bash(grep:*), Glob, Grep, Read, Task
description: Trace a request end-to-end through all Plue services
model: claude-sonnet-4-20250514
---

# Request Tracing Agent

Trace a request through the entire Plue stack: Edge -> API -> Database -> Response.

## Arguments

- `<request_id>`: UUID of the request to trace
- `<path>`: API path to trace (e.g., `/api/v1/repos/owner/name`)
- `--live`: Make a live request and trace it

Arguments: $ARGUMENTS

## Quick Reference

```
/trace-request abc123-def456           # Trace by request ID
/trace-request /api/v1/repos/user/repo # Trace specific endpoint
/trace-request --live /api/v1/user     # Make request and trace
```

## How Tracing Works

Plue uses structured logging with request correlation:

```
Request Flow:
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Client  │ ──► │   Edge   │ ──► │   API    │ ──► │ Database │
└──────────┘     │ (CF/CDN) │     │  (Zig)   │     │ (Postgres)│
                 └──────────┘     └──────────┘     └──────────┘
                      │                │                │
                      ▼                ▼                ▼
                 [x-request-id]  [request_id in logs] [query logs]
```

Each request is tagged with:
- `request_id`: UUID for correlation
- `path`: API endpoint
- `method`: HTTP method
- `duration_ms`: Request duration
- `status`: HTTP status code

## Phase 1: Identify the Request

### Option A: By Request ID

If you have a request_id (from logs, error reports, etc.):

```
Use logs-mcp: trace_request(request_id="YOUR-REQUEST-ID")
```

### Option B: By Endpoint and Time

Find requests to a specific endpoint:

```
Use logs-mcp: search_logs(
  service="api",
  contains="/api/v1/your/endpoint",
  start="1h"
)
```

### Option C: Live Request

Make a request and capture the trace:

```bash
# Make request and capture request ID from response headers
curl -v http://localhost:4000/api/v1/user 2>&1 | grep -i x-request-id

# Or with timing
curl -w "@-" -o /dev/null -s http://localhost:4000/api/v1/user <<'EOF'
     time_namelookup:  %{time_namelookup}s\n
        time_connect:  %{time_connect}s\n
     time_appconnect:  %{time_appconnect}s\n
    time_pretransfer:  %{time_pretransfer}s\n
       time_redirect:  %{time_redirect}s\n
  time_starttransfer:  %{time_starttransfer}s\n
          time_total:  %{time_total}s\n
EOF
```

## Phase 2: Gather All Log Entries

### From Loki

```
Use logs-mcp: trace_request(request_id="UUID")
```

This returns logs from all services that processed this request.

### Expected Log Entries

For a typical API request, you should see:

1. **Request received**
   ```
   [api] INFO request_start path=/api/v1/repos request_id=xxx method=GET
   ```

2. **Auth check**
   ```
   [api] DEBUG auth_check user_id=123 request_id=xxx
   ```

3. **Database queries**
   ```
   [api] DEBUG db_query query="SELECT..." duration_ms=5 request_id=xxx
   ```

4. **Response sent**
   ```
   [api] INFO request_complete status=200 duration_ms=45 request_id=xxx
   ```

## Phase 3: Analyze the Trace

### Build a Timeline

```
[TIME]      [SERVICE]   [EVENT]                      [DURATION]
──────────────────────────────────────────────────────────────
00:00.000   api         Request received             -
00:00.002   api         Auth validated               2ms
00:00.005   api         DB query started             -
00:00.015   postgres    Query executed               10ms
00:00.018   api         Response serialization       3ms
00:00.020   api         Response sent                -
──────────────────────────────────────────────────────────────
Total: 20ms
```

### Check for Issues

1. **Slow database queries** (>100ms)
   - Look for missing indexes
   - Check query complexity

2. **Auth delays** (>50ms)
   - Session lookup issues
   - Token validation problems

3. **Serialization time** (>20ms)
   - Large response payloads
   - Inefficient JSON encoding

4. **Gaps in timeline**
   - Missing log entries
   - External service calls
   - Blocking operations

## Phase 4: Database Query Analysis

For requests that involve database queries:

```sql
-- Find recent slow queries
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
WHERE query LIKE '%your_table%'
ORDER BY mean_time DESC
LIMIT 10;
```

Or use database-mcp:
```
explain_query(sql="YOUR QUERY HERE")
```

## Phase 5: Metrics Correlation

Cross-reference with Prometheus metrics:

```
Use prometheus-mcp: prometheus_query_range(
  query='plue_http_request_duration_ms_bucket{path="/api/v1/your/endpoint"}',
  start="1h"
)
```

This shows if the request's latency is typical or an outlier.

## Trace Report Template

After tracing, provide a summary:

```markdown
## Request Trace Report

**Request ID**: `abc123-def456`
**Endpoint**: `GET /api/v1/repos/owner/name`
**Status**: 200 OK
**Total Duration**: 45ms

### Timeline

| Time | Service | Event | Duration |
|------|---------|-------|----------|
| 0ms | API | Request received | - |
| 2ms | API | Auth validated | 2ms |
| 5ms | DB | Query: SELECT repo | 12ms |
| 17ms | DB | Query: SELECT commits | 8ms |
| 25ms | API | Response serialized | 15ms |
| 40ms | API | Response sent | - |

### Breakdown

- Auth: 2ms (4%)
- Database: 20ms (44%)
- Serialization: 15ms (33%)
- Network/Other: 8ms (18%)

### Database Queries

1. `SELECT * FROM repositories WHERE owner_id = $1 AND name = $2`
   - Duration: 12ms
   - Rows: 1

2. `SELECT * FROM commits WHERE repo_id = $1 ORDER BY created_at DESC LIMIT 10`
   - Duration: 8ms
   - Rows: 10

### Findings

- [x] Request completed successfully
- [ ] No slow queries detected
- [ ] Auth performed efficiently

### Recommendations

- Consider caching repository lookups
- Add index on commits(repo_id, created_at)
```

## Debugging Specific Issues

### Issue: Request Returns 500

1. Find the request in logs
   ```
   Use logs-mcp: search_logs(service="api", level="error", start="1h")
   ```

2. Get the stack trace
   ```
   Use logs-mcp: search_exceptions(start="1h")
   ```

3. Check database errors
   ```
   Use database-mcp: check_connections()
   ```

### Issue: Request Times Out

1. Check where time is spent
   ```
   Use prometheus-mcp: latency_analysis()
   ```

2. Look for blocking operations
   ```
   Use logs-mcp: find_slow_requests(threshold_ms=5000)
   ```

3. Check external calls
   ```
   Use logs-mcp: search_logs(contains="external", start="1h")
   ```

### Issue: Intermittent Failures

1. Compare successful vs failed requests
   ```
   # Find both
   Use logs-mcp: search_logs(contains="request_id=xxx")
   ```

2. Check for patterns
   - Time of day
   - Specific users
   - Request payload size

3. Check metrics for anomalies
   ```
   Use prometheus-mcp: error_analysis(duration="6h")
   ```

## Tracing Workflow Requests

For workflow-related requests:

```
/trace-request /api/v1/workflows/run
```

Additional workflow-specific checks:

1. **Trigger processing**
   ```
   Use logs-mcp: workflow_logs(run_id=X)
   ```

2. **Queue submission**
   ```
   Use workflows-mcp: get_run_details(run_id=X)
   ```

3. **Step execution**
   ```
   Use workflows-mcp: get_step_logs(step_id=Y)
   ```

## Quick Commands

```bash
# Find recent errors
docker logs plue-api 2>&1 | grep -i error | tail -20

# Find specific request
docker logs plue-api 2>&1 | grep "request_id=YOUR_ID"

# Check response times
curl -w "Total: %{time_total}s\n" -o /dev/null -s http://localhost:4000/api/v1/user

# Database query log
docker exec plue-postgres psql -U postgres -d plue -c "
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10
"
```
