# Fix Workflow Command Injection Vulnerability

## Priority: CRITICAL | Security

## Problem

The workflow execution system uses `sh -c` to run commands, allowing shell metacharacter injection:

**Server (Zig):** `server/src/workflows/executor.zig:948-949`
```zig
const argv = [_][]const u8{ "sh", "-c", cmd };
```

**Runner (Python):** `runner/src/workflow.py:95-104`
```python
result = subprocess.run(command, shell=True, ...)
```

Malicious workflow definitions can execute arbitrary commands on the server.

## Task

1. **Analyze current command execution paths:**
   - Read `server/src/workflows/executor.zig` - find all `sh -c` usage
   - Read `runner/src/workflow.py` - find all `shell=True` usage
   - Trace where `cmd` values originate (workflow YAML → database → executor)

2. **Implement safe command execution in Zig:**
   - Parse command strings into argv arrays (handle quoting properly)
   - Use `std.process.Child` with explicit argv (no shell interpretation)
   - Create a command parser that handles common shell constructs safely
   - Reject or escape shell metacharacters: `; | & $ \` > < ( ) { } [ ]`

3. **Implement safe command execution in Python:**
   - Change `shell=True` to `shell=False`
   - Use `shlex.split()` to parse command strings
   - Validate commands against allowlist of safe patterns
   - Add logging for all executed commands

4. **Add command validation layer:**
   - Create `server/src/workflows/command_validator.zig`
   - Implement allowlist of safe command prefixes (npm, pip, zig, cargo, etc.)
   - Block dangerous commands (curl to external, wget, nc, etc.)
   - Add configurable strictness levels

5. **Write security tests:**
   - Test common injection payloads: `; rm -rf /`, `$(whoami)`, `` `id` ``
   - Test command chaining: `cmd1 && cmd2`, `cmd1 || cmd2`
   - Test output redirection: `> /etc/passwd`, `>> ~/.bashrc`
   - Ensure all tests FAIL before fix and PASS after

6. **Update documentation:**
   - Document safe command patterns in workflow YAML
   - Add security warnings about command execution

## Acceptance Criteria

- [ ] No `sh -c` or `shell=True` in production code paths
- [ ] Command parsing handles quoted arguments correctly
- [ ] Injection attempts are blocked and logged
- [ ] All new security tests pass
- [ ] Existing workflow tests still pass
