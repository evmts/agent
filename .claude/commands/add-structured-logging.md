# Implement Structured Logging

## Priority: MEDIUM | Observability

## Problem

Logging is inconsistent across components:
- Server uses `std.debug.print` in some places
- Runner uses basic Python logging
- Edge worker has no logging
- No request tracing across services

## Task

### Phase 1: Define Logging Standard

1. **Create logging format specification:**
   ```json
   {
     "timestamp": "2024-01-15T10:30:00.000Z",
     "level": "info|warn|error|debug",
     "service": "api|web|runner|edge",
     "request_id": "uuid",
     "user_id": "optional",
     "message": "Human readable message",
     "context": {
       "key": "value"
     },
     "error": {
       "type": "ErrorType",
       "message": "Error message",
       "stack": "optional stack trace"
     }
   }
   ```

### Phase 2: Server Logging

2. **Replace debug.print with structured logging:**
   ```zig
   // server/src/lib/logger.zig

   pub const Logger = struct {
       service: []const u8,
       request_id: ?[]const u8,
       user_id: ?i32,

       pub fn info(self: Logger, message: []const u8, context: anytype) void {
           self.log(.info, message, context);
       }

       pub fn err(self: Logger, message: []const u8, context: anytype) void {
           self.log(.err, message, context);
       }

       fn log(self: Logger, level: std.log.Level, message: []const u8, context: anytype) void {
           const timestamp = std.time.timestamp();

           std.json.stringify(.{
               .timestamp = timestamp,
               .level = @tagName(level),
               .service = self.service,
               .request_id = self.request_id,
               .user_id = self.user_id,
               .message = message,
               .context = context,
           }, .{}, std.io.getStdErr().writer()) catch return;

           std.io.getStdErr().writer().writeByte('\n') catch return;
       }
   };
   ```

3. **Add request ID middleware:**
   ```zig
   // server/src/middleware/request_id.zig

   pub fn middleware(ctx: *Context, req: *Request) !void {
       const request_id = req.header("X-Request-Id") orelse
           generateUuid();

       ctx.request_id = request_id;
       ctx.logger = Logger{
           .service = "api",
           .request_id = request_id,
           .user_id = if (ctx.user) |u| u.id else null,
       };
   }
   ```

### Phase 3: Runner Logging

4. **Implement structured Python logging:**
   ```python
   # runner/src/logging_config.py

   import json
   import logging
   import sys
   from datetime import datetime

   class StructuredFormatter(logging.Formatter):
       def format(self, record):
           log_entry = {
               "timestamp": datetime.utcnow().isoformat() + "Z",
               "level": record.levelname.lower(),
               "service": "runner",
               "request_id": getattr(record, "request_id", None),
               "task_id": getattr(record, "task_id", None),
               "message": record.getMessage(),
           }

           if record.exc_info:
               log_entry["error"] = {
                   "type": record.exc_info[0].__name__,
                   "message": str(record.exc_info[1]),
                   "stack": self.formatException(record.exc_info),
               }

           if hasattr(record, "context"):
               log_entry["context"] = record.context

           return json.dumps(log_entry)

   def configure_logging():
       handler = logging.StreamHandler(sys.stderr)
       handler.setFormatter(StructuredFormatter())

       root = logging.getLogger()
       root.handlers = [handler]
       root.setLevel(logging.INFO)
   ```

5. **Add context to runner logs:**
   ```python
   # runner/src/agent.py

   class ContextLogger:
       def __init__(self, task_id: str):
           self.logger = logging.getLogger(__name__)
           self.task_id = task_id

       def info(self, message: str, **context):
           self.logger.info(message, extra={
               "task_id": self.task_id,
               "context": context,
           })
   ```

### Phase 4: Edge Worker Logging

6. **Add structured logging to edge:**
   ```typescript
   // edge/logging.ts

   interface LogEntry {
     timestamp: string;
     level: 'info' | 'warn' | 'error';
     service: 'edge';
     request_id?: string;
     message: string;
     context?: Record<string, unknown>;
     duration_ms?: number;
   }

   export function log(entry: Omit<LogEntry, 'timestamp' | 'service'>): void {
     console.log(JSON.stringify({
       ...entry,
       timestamp: new Date().toISOString(),
       service: 'edge',
     }));
   }

   export function logRequest(
     request: Request,
     response: Response,
     startTime: number
   ): void {
     log({
       level: 'info',
       request_id: request.headers.get('X-Request-Id') || undefined,
       message: 'Request completed',
       context: {
         method: request.method,
         url: request.url,
         status: response.status,
         cache_status: response.headers.get('X-Cache-Status'),
       },
       duration_ms: Date.now() - startTime,
     });
   }
   ```

### Phase 5: Request Tracing

7. **Propagate request ID across services:**
   ```typescript
   // edge/index.ts

   async function handleRequest(request: Request, env: Env): Promise<Response> {
     const requestId = request.headers.get('X-Request-Id') || crypto.randomUUID();

     // Add to outgoing request
     const headers = new Headers(request.headers);
     headers.set('X-Request-Id', requestId);

     const response = await proxyToOrigin(new Request(request.url, {
       ...request,
       headers,
     }), env);

     // Add to response
     const responseHeaders = new Headers(response.headers);
     responseHeaders.set('X-Request-Id', requestId);

     return new Response(response.body, {
       status: response.status,
       headers: responseHeaders,
     });
   }
   ```

8. **Create log aggregation query:**
   ```bash
   # Loki query to trace request across services
   {service=~"api|web|runner|edge"} | json | request_id="abc-123"
   ```

### Phase 6: Grafana Dashboard

9. **Create logging dashboard:**
   ```json
   {
     "title": "Request Tracing",
     "panels": [
       {
         "title": "Request Flow",
         "type": "logs",
         "targets": [
           {
             "expr": "{service=~\".*\"} | json | request_id=\"$request_id\"",
             "legendFormat": "{{service}}"
           }
         ]
       }
     ]
   }
   ```

## Acceptance Criteria

- [ ] All services use structured JSON logging
- [ ] Request ID propagated across all services
- [ ] Error logs include stack traces
- [ ] Loki can aggregate logs by request_id
- [ ] Grafana dashboard for tracing
- [ ] No `std.debug.print` or `console.log` without structure
