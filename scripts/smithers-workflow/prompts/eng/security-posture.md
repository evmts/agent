# Localhost Security Posture

HTTP/WS server runs with no auth. This is intentional for a power-user tool but the security contract must be explicit.

## Binding

- **MUST bind to `127.0.0.1` only.** NEVER `0.0.0.0` or `::`.
- Use a random high port (ephemeral range 49152-65535) by default.
- If a fixed port is configured, warn at startup if another process is already bound.

## Access Control

- No authentication required for localhost connections (YOLO mode).
- Optional per-session token: if enabled, passed via `Authorization: Bearer <token>` header or `?token=<token>` query param. Token generated at server start, printed to stdout.
- Token mode is opt-in via config. Default: no token (localhost trust model).

## Filesystem Scope

- Server MUST NOT read/write outside the workspace root unless explicitly enabled via config.
- Workspace root = directory containing `.jj/`, `.git/`, or `CLAUDE.md` (walked upward from cwd).
- Terminal PTY sessions inherit workspace root as cwd.

## Future: Sandbox Mode

- Post-MVP: sandboxed execution (filesystem allowlist, network restrictions, process limits).
- Current MVP: YOLO mode only. No sandbox.

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| Remote access to API | Bind 127.0.0.1 only |
| Other local users on shared machine | macOS user isolation (default); optional token |
| Malicious web page accessing API | CORS: reject non-localhost origins |
| Path traversal | Restrict to workspace root |
