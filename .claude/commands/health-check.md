---
allowed-tools: Bash(curl:*), Bash(docker:*), Bash(lsof:*), Bash(ps:*), Bash(zig:*), Glob, Grep, Read, Task
description: Quick system health diagnostics for all Plue services
model: claude-sonnet-4-20250514
---

# Health Check Agent

Perform comprehensive health checks across all Plue services and infrastructure.

## Arguments

- `--quick`: Fast check, essentials only (default)
- `--full`: Complete diagnostic including metrics and logs
- `--fix`: Attempt to auto-fix common issues

Arguments: $ARGUMENTS

## Quick Health Check

Run these checks in order:

### 1. Core Services

```bash
echo "=== Core Services ==="

# API Server (Zig)
echo -n "API Server (4000): "
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/health 2>/dev/null || echo "DOWN"

# Web UI (Astro)
echo -n "Web UI (3000): "
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "DOWN"

# PostgreSQL
echo -n "PostgreSQL (54321): "
docker exec plue-postgres pg_isready -U postgres 2>/dev/null && echo "UP" || echo "DOWN"
```

### 2. Monitoring Stack

```bash
echo "=== Monitoring ==="

# Prometheus
echo -n "Prometheus (9090): "
curl -s http://localhost:9090/-/ready 2>/dev/null && echo "UP" || echo "DOWN"

# Grafana
echo -n "Grafana (3001): "
curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health 2>/dev/null || echo "DOWN"

# Loki
echo -n "Loki (3100): "
curl -s http://localhost:3100/ready 2>/dev/null && echo "UP" || echo "DOWN"
```

### 3. Docker Containers

```bash
echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "plue|postgres|prometheus|grafana|loki"
```

### 4. Database Connectivity

```bash
echo "=== Database ==="
# Check if we can connect and query
docker exec plue-postgres psql -U postgres -d plue -c "SELECT 1 as health" 2>/dev/null && echo "Query OK" || echo "Query FAILED"

# Check connection count
docker exec plue-postgres psql -U postgres -d plue -c "SELECT count(*) as connections FROM pg_stat_activity WHERE datname = 'plue'" 2>/dev/null
```

### 5. Workflow System

```bash
echo "=== Workflow System ==="

# Check workflow tables exist
docker exec plue-postgres psql -U postgres -d plue -c "
SELECT
  (SELECT count(*) FROM workflow_definitions) as definitions,
  (SELECT count(*) FROM workflow_runs) as runs,
  (SELECT count(*) FROM workflow_runs WHERE status = 'running') as running
" 2>/dev/null || echo "Workflow tables may not exist"

# Check for stuck runs
docker exec plue-postgres psql -U postgres -d plue -c "
SELECT count(*) as stuck_runs
FROM workflow_runs
WHERE status = 'running'
  AND started_at < NOW() - INTERVAL '1 hour'
" 2>/dev/null
```

## Full Diagnostic (--full)

### Metrics Check

Use prometheus-mcp tools:

```
service_health()        - Check all service UP status
error_analysis()        - Recent error patterns
latency_analysis()      - Response time analysis
```

### Log Analysis

Use logs-mcp tools:

```
find_errors(start="1h")           - Recent errors
log_stats()                        - Log volume by service
search_exceptions(start="1h")     - Stack traces
```

### Database Deep Check

Use database-mcp tools:

```
db_stats()              - Database size, connections
check_connections()     - Active queries
recent_activity()       - Recent changes
```

## Common Issues & Fixes

### Issue: API Server Not Responding

**Symptoms:**
- curl to :4000 fails
- "Connection refused"

**Check:**
```bash
lsof -i :4000
ps aux | grep "zig"
```

**Fix:**
```bash
# Restart the server
zig build run
```

### Issue: Database Connection Errors

**Symptoms:**
- "connection refused" errors
- API returns 500 errors

**Check:**
```bash
docker ps | grep postgres
docker logs plue-postgres --tail 20
```

**Fix:**
```bash
# Restart PostgreSQL
docker restart plue-postgres

# Or full restart
docker-compose -f infra/docker/docker-compose.yaml restart postgres
```

### Issue: Prometheus Not Scraping

**Symptoms:**
- Metrics missing in Grafana
- "No data" in dashboards

**Check:**
```bash
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Fix:**
```bash
# Check prometheus config
cat infra/monitoring/prometheus/prometheus.yml

# Restart prometheus
docker restart plue-prometheus
```

### Issue: Workflow Runs Stuck

**Symptoms:**
- Runs stay in "pending" or "running"
- No progress for >10 minutes

**Check:**
```bash
docker exec plue-postgres psql -U postgres -d plue -c "
SELECT id, status, started_at,
       EXTRACT(EPOCH FROM (NOW() - started_at))/60 as minutes_running
FROM workflow_runs
WHERE status IN ('pending', 'running')
ORDER BY created_at
"
```

**Fix:**
```bash
# Mark stale runs as failed
docker exec plue-postgres psql -U postgres -d plue -c "
UPDATE workflow_runs
SET status = 'failed',
    error_message = 'Marked as failed due to timeout',
    completed_at = NOW()
WHERE status = 'running'
  AND started_at < NOW() - INTERVAL '1 hour'
"
```

### Issue: High Memory Usage

**Symptoms:**
- System slow
- OOM errors

**Check:**
```bash
docker stats --no-stream
free -h
```

**Fix:**
```bash
# Restart heavy containers
docker restart plue-api plue-grafana

# Clear docker cache if needed
docker system prune -f
```

### Issue: Logs Not Appearing

**Symptoms:**
- Loki queries return empty
- Grafana shows "No data"

**Check:**
```bash
# Check promtail
docker logs plue-promtail --tail 20

# Check loki
curl http://localhost:3100/ready
curl http://localhost:3100/loki/api/v1/labels
```

**Fix:**
```bash
# Restart log pipeline
docker restart plue-promtail plue-loki
```

## Health Report Template

After running checks, provide a summary:

```markdown
## System Health Report

**Timestamp**: [datetime]
**Overall Status**: [HEALTHY / DEGRADED / UNHEALTHY]

### Service Status
| Service | Port | Status | Notes |
|---------|------|--------|-------|
| API | 4000 | UP/DOWN | |
| Web | 3000 | UP/DOWN | |
| PostgreSQL | 54321 | UP/DOWN | |
| Prometheus | 9090 | UP/DOWN | |
| Grafana | 3001 | UP/DOWN | |
| Loki | 3100 | UP/DOWN | |

### Key Metrics
- Error rate (5m): X%
- Avg latency: Xms
- Active connections: X

### Issues Found
1. [Issue description]
   - Impact: [low/medium/high]
   - Recommendation: [action]

### Recommendations
- [Action item 1]
- [Action item 2]
```

## Automated Recovery (--fix)

If `--fix` is passed, attempt automatic recovery:

1. **Restart failed containers**
   ```bash
   docker-compose -f infra/docker/docker-compose.yaml up -d
   ```

2. **Clear stuck workflow runs**
   ```sql
   UPDATE workflow_runs SET status = 'failed' WHERE status = 'running' AND started_at < NOW() - INTERVAL '1 hour';
   ```

3. **Vacuum database**
   ```bash
   docker exec plue-postgres psql -U postgres -d plue -c "VACUUM ANALYZE"
   ```

4. **Restart monitoring**
   ```bash
   docker restart plue-prometheus plue-grafana plue-loki
   ```

## Quick Commands

```bash
# Start all services
zig build run

# Check all containers
docker-compose -f infra/docker/docker-compose.yaml ps

# View all logs
docker-compose -f infra/docker/docker-compose.yaml logs -f

# Restart everything
docker-compose -f infra/docker/docker-compose.yaml restart

# Full rebuild
docker-compose -f infra/docker/docker-compose.yaml down && zig build run
```
