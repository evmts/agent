# Interactive PTY Execution

<metadata>
  <priority>high</priority>
  <category>tool-implementation</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, core/</affects>
</metadata>

## Objective

Implement `unified_exec` and `write_stdin` tools for interactive PTY-based command execution, allowing the agent to run and interact with long-running processes.

<context>
Codex provides `unified_exec` for running interactive commands in a pseudo-terminal (PTY). This enables:
- Running interactive programs (npm, pip, git interactive rebase)
- Sending input to running processes
- Managing multiple concurrent sessions
- Handling programs that require TTY

Unlike the basic shell tool, unified_exec maintains persistent sessions that can receive additional input via `write_stdin`.
</context>

## Requirements

<functional-requirements>
1. `unified_exec` tool:
   - Start command in PTY
   - Return session ID for follow-up interactions
   - Stream initial output
   - Configure timeout and output limits
   - Support shell selection
2. `write_stdin` tool:
   - Write input to running session
   - Return new output since last read
   - Handle session not found gracefully
3. Session management:
   - Multiple concurrent PTY sessions
   - Session timeout and cleanup
   - Graceful process termination
4. Output handling:
   - Token-limited output capture
   - Support for ANSI escape codes
   - Configurable yield time
</functional-requirements>

<technical-requirements>
1. Use `pty` library for pseudo-terminal creation
2. Implement session registry for tracking active PTYs
3. Async I/O for non-blocking read/write
4. Process lifecycle management (start, signal, kill)
5. Output buffering with configurable limits
6. Thread-safe session access
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/pty_exec.py` (CREATE) - PTY execution tools
- `agent/agent.py` - Register unified_exec and write_stdin tools
- `core/pty_manager.py` (CREATE) - PTY session management
- `tests/test_pty_exec.py` (CREATE) - Test suite
</files-to-modify>

<tool-schemas>
```python
# unified_exec tool
async def unified_exec(
    cmd: str,
    workdir: Optional[str] = None,
    shell: Optional[str] = None,
    login: bool = False,
    yield_time_ms: int = 100,
    max_output_tokens: int = 10000,
    timeout_ms: Optional[int] = None,
) -> str:
    """
    Run a command in an interactive PTY session.

    Args:
        cmd: Command to execute
        workdir: Working directory (defaults to session cwd)
        shell: Shell to use (defaults to user's shell)
        login: Use login shell
        yield_time_ms: Time to wait for output before returning
        max_output_tokens: Maximum output tokens to capture
        timeout_ms: Command timeout in milliseconds

    Returns:
        JSON with session_id, output, and status
    """

# write_stdin tool
async def write_stdin(
    session_id: str,
    chars: str,
    yield_time_ms: int = 100,
    max_output_tokens: int = 10000,
) -> str:
    """
    Write input to a running PTY session.

    Args:
        session_id: PTY session ID from unified_exec
        chars: Characters to write (can include special chars like \\n)
        yield_time_ms: Time to wait for output
        max_output_tokens: Maximum output tokens to return

    Returns:
        JSON with new output since last read
    """
```
</tool-schemas>

<pty-manager>
```python
import asyncio
import os
import pty
import select
import signal
from dataclasses import dataclass, field
from typing import Optional
import uuid

@dataclass
class PTYSession:
    id: str
    master_fd: int
    slave_fd: int
    pid: int
    output_buffer: str = ""
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)

class PTYManager:
    def __init__(self, max_sessions: int = 10, session_timeout: float = 300):
        self.sessions: dict[str, PTYSession] = {}
        self.max_sessions = max_sessions
        self.session_timeout = session_timeout
        self._lock = asyncio.Lock()

    async def create_session(
        self,
        cmd: str,
        workdir: Optional[str] = None,
        shell: Optional[str] = None,
        env: Optional[dict] = None,
    ) -> PTYSession:
        """Create a new PTY session."""
        async with self._lock:
            # Cleanup old sessions
            await self._cleanup_stale_sessions()

            if len(self.sessions) >= self.max_sessions:
                raise RuntimeError(f"Maximum PTY sessions ({self.max_sessions}) reached")

            session_id = str(uuid.uuid4())[:8]

            # Fork PTY
            pid, master_fd = pty.fork()

            if pid == 0:
                # Child process
                if workdir:
                    os.chdir(workdir)
                if env:
                    os.environ.update(env)

                shell = shell or os.environ.get("SHELL", "/bin/bash")
                os.execvp(shell, [shell, "-c", cmd])
            else:
                # Parent process
                session = PTYSession(
                    id=session_id,
                    master_fd=master_fd,
                    slave_fd=-1,  # Not used in parent
                    pid=pid,
                )
                self.sessions[session_id] = session
                return session

    async def write_input(self, session_id: str, data: str) -> None:
        """Write input to PTY session."""
        session = self.sessions.get(session_id)
        if not session:
            raise KeyError(f"Session {session_id} not found")

        os.write(session.master_fd, data.encode())
        session.last_activity = time.time()

    async def read_output(
        self,
        session_id: str,
        timeout_ms: int = 100,
        max_bytes: int = 65536,
    ) -> str:
        """Read available output from PTY session."""
        session = self.sessions.get(session_id)
        if not session:
            raise KeyError(f"Session {session_id} not found")

        output = []
        deadline = time.time() + (timeout_ms / 1000)

        while time.time() < deadline:
            readable, _, _ = select.select([session.master_fd], [], [], 0.01)
            if readable:
                try:
                    data = os.read(session.master_fd, 4096)
                    if data:
                        output.append(data.decode("utf-8", errors="replace"))
                except OSError:
                    break
            else:
                await asyncio.sleep(0.01)

        result = "".join(output)
        session.output_buffer += result
        session.last_activity = time.time()
        return result

    async def close_session(self, session_id: str) -> None:
        """Close and cleanup PTY session."""
        async with self._lock:
            session = self.sessions.pop(session_id, None)
            if session:
                try:
                    os.kill(session.pid, signal.SIGTERM)
                    os.close(session.master_fd)
                except OSError:
                    pass

    async def _cleanup_stale_sessions(self) -> None:
        """Remove sessions that have timed out."""
        now = time.time()
        stale = [
            sid for sid, s in self.sessions.items()
            if now - s.last_activity > self.session_timeout
        ]
        for sid in stale:
            await self.close_session(sid)
```
</pty-manager>

<example-usage>
```python
# Start an interactive npm install
result = await unified_exec(
    cmd="npm install",
    workdir="/path/to/project",
    yield_time_ms=5000,  # Wait 5s for initial output
)
# result: {"session_id": "abc123", "output": "npm WARN ...", "running": true}

# If prompted for input, send response
result = await write_stdin(
    session_id="abc123",
    chars="yes\n",
    yield_time_ms=2000,
)
# result: {"output": "Installing dependencies...", "running": true}

# Check final output
result = await write_stdin(
    session_id="abc123",
    chars="",  # Just read, no input
    yield_time_ms=1000,
)
# result: {"output": "Done!", "running": false, "exit_code": 0}
```
</example-usage>

## Acceptance Criteria

<criteria>
- [ ] `unified_exec` starts command in PTY
- [ ] Returns session_id for follow-up interactions
- [ ] `write_stdin` writes input to session
- [ ] Output correctly captured and returned
- [ ] Multiple concurrent sessions supported
- [ ] Session timeout and cleanup works
- [ ] Handles process exit gracefully
- [ ] Works with interactive programs (less, vim, etc.)
- [ ] ANSI escape codes preserved
- [ ] Token limiting prevents output overflow
- [ ] Thread-safe session access
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test with interactive programs (npm, python REPL, etc.)
3. Test session timeout and cleanup
4. Test multiple concurrent sessions
5. Run `pytest tests/test_pty_exec.py` to ensure all passes
6. Rename this file from `35-interactive-pty-exec.md` to `35-interactive-pty-exec.complete.md`
</completion>
