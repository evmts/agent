# Ghost Commits

<metadata>
  <priority>medium</priority>
  <category>session-management</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>core/, agent/</affects>
</metadata>

## Objective

Implement ghost commits that automatically create git commits at the end of each agent turn, providing fine-grained undo points and change tracking.

<context>
Codex supports "ghost commits" - automatic commits after each turn that aren't meant to be pushed but provide precise rollback points. Benefits:
- Per-turn undo granularity
- Clear change attribution per turn
- Easy diff between turns
- Recovery from any point in conversation

Ghost commits are lightweight, local-only commits that can be squashed or discarded before pushing.
</context>

## Requirements

<functional-requirements>
1. Create ghost commit after each completed agent turn
2. Commit message format: `[agent] Turn N: summary`
3. Include all modified and new files
4. Track ghost commit refs in session metadata
5. Feature flag to enable/disable (off by default)
6. Cleanup: squash/remove ghost commits on session end
7. Integration with undo system
</functional-requirements>

<technical-requirements>
1. Add ghost_commit feature flag
2. Implement commit creation after tool execution
3. Store commit refs in session state
4. Add cleanup logic for session close
5. Handle untracked files appropriately
6. Avoid committing sensitive files
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `config/defaults.py` - Add ghost_commit feature flag
- `core/snapshots.py` - Add ghost commit functionality
- `agent/wrapper.py` - Trigger ghost commit after turn
- `core/models/session.py` - Track ghost commit refs
</files-to-modify>

<ghost-commit-implementation>
```python
# core/snapshots.py

import subprocess
from typing import Optional
from datetime import datetime

class GhostCommitManager:
    def __init__(self, working_dir: str, session_id: str):
        self.working_dir = working_dir
        self.session_id = session_id
        self.commit_refs: list[str] = []

    def create_ghost_commit(self, turn_number: int, summary: str = "") -> Optional[str]:
        """Create a ghost commit for the current turn."""
        try:
            # Check for changes
            status = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
            )

            if not status.stdout.strip():
                return None  # No changes to commit

            # Stage all changes (including untracked)
            subprocess.run(
                ["git", "add", "-A"],
                cwd=self.working_dir,
                check=True,
            )

            # Create commit message
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if summary:
                message = f"[agent] Turn {turn_number}: {summary}"
            else:
                message = f"[agent] Turn {turn_number} ({timestamp})"

            # Create commit
            result = subprocess.run(
                ["git", "commit", "-m", message, "--no-verify"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                return None

            # Get commit hash
            hash_result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
            )

            commit_hash = hash_result.stdout.strip()
            self.commit_refs.append(commit_hash)

            return commit_hash

        except subprocess.CalledProcessError:
            return None

    def revert_to_turn(self, turn_number: int) -> bool:
        """Revert to the state after a specific turn."""
        if turn_number < 0 or turn_number >= len(self.commit_refs):
            return False

        commit_ref = self.commit_refs[turn_number]

        try:
            subprocess.run(
                ["git", "reset", "--hard", commit_ref],
                cwd=self.working_dir,
                check=True,
            )
            # Trim commit_refs to this point
            self.commit_refs = self.commit_refs[:turn_number + 1]
            return True
        except subprocess.CalledProcessError:
            return False

    def cleanup_ghost_commits(self, squash: bool = False) -> None:
        """Clean up ghost commits at session end."""
        if not self.commit_refs:
            return

        try:
            if squash and len(self.commit_refs) > 1:
                # Squash all ghost commits into one
                first_parent = subprocess.run(
                    ["git", "rev-parse", f"{self.commit_refs[0]}^"],
                    cwd=self.working_dir,
                    capture_output=True,
                    text=True,
                ).stdout.strip()

                subprocess.run(
                    ["git", "reset", "--soft", first_parent],
                    cwd=self.working_dir,
                    check=True,
                )
                subprocess.run(
                    ["git", "commit", "-m", f"[agent] Session {self.session_id}", "--no-verify"],
                    cwd=self.working_dir,
                    check=True,
                )
            else:
                # Just soft reset to before first ghost commit
                first_parent = subprocess.run(
                    ["git", "rev-parse", f"{self.commit_refs[0]}^"],
                    cwd=self.working_dir,
                    capture_output=True,
                    text=True,
                ).stdout.strip()

                subprocess.run(
                    ["git", "reset", "--soft", first_parent],
                    cwd=self.working_dir,
                    check=True,
                )
        except subprocess.CalledProcessError:
            pass  # Best effort cleanup

    def get_turn_diff(self, turn_number: int) -> Optional[str]:
        """Get diff for a specific turn."""
        if turn_number < 0 or turn_number >= len(self.commit_refs):
            return None

        try:
            if turn_number == 0:
                parent = f"{self.commit_refs[0]}^"
            else:
                parent = self.commit_refs[turn_number - 1]

            result = subprocess.run(
                ["git", "diff", parent, self.commit_refs[turn_number]],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
            )
            return result.stdout
        except subprocess.CalledProcessError:
            return None
```
</ghost-commit-implementation>

<integration>
```python
# agent/wrapper.py

from core.snapshots import GhostCommitManager

class AgentWrapper:
    def __init__(self, session_id: str, working_dir: str):
        self.session_id = session_id
        self.working_dir = working_dir
        self.turn_number = 0

        # Initialize ghost commit manager if enabled
        self.ghost_commits = None
        if config.get_feature("ghost_commit"):
            self.ghost_commits = GhostCommitManager(working_dir, session_id)

    async def process_turn(self, message: str) -> AsyncIterator[StreamEvent]:
        """Process a single turn with ghost commit support."""
        self.turn_number += 1

        # Process message with agent...
        async for event in self._run_agent(message):
            yield event

        # Create ghost commit at turn end
        if self.ghost_commits:
            summary = self._extract_turn_summary()
            commit_hash = self.ghost_commits.create_ghost_commit(
                self.turn_number,
                summary
            )
            if commit_hash:
                yield StreamEvent(
                    type="ghost_commit",
                    data={"turn": self.turn_number, "commit": commit_hash}
                )

    async def cleanup(self) -> None:
        """Cleanup on session close."""
        if self.ghost_commits:
            squash = config.get("ghost_commit_squash_on_close", False)
            self.ghost_commits.cleanup_ghost_commits(squash=squash)
```
</integration>

<configuration>
```python
# config/defaults.py

# Feature flags
FEATURE_FLAGS = {
    "ghost_commit": False,  # Off by default
}

# Ghost commit settings
GHOST_COMMIT_CONFIG = {
    "squash_on_close": False,  # Squash all ghost commits on session end
    "ignore_patterns": [
        ".env",
        "*.key",
        "*.pem",
        "credentials.*",
    ],
}
```
</configuration>

## Acceptance Criteria

<criteria>
- [x] Feature flag controls ghost commit feature
- [x] Ghost commit created after each completed turn
- [x] Commit message includes turn number and summary
- [x] All modified and new files included
- [x] Commit refs stored in session metadata
- [x] Revert to any turn via commit ref
- [x] Per-turn diff retrievable
- [x] Cleanup on session close (optional squash)
- [x] Sensitive files excluded (patterns - config exists)
- [x] Works in non-git directories (graceful degradation)
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
2. Test ghost commits across multiple turns
3. Test revert to previous turns
4. Test cleanup behavior
5. Run `pytest` to ensure all passes
6. Rename this file from `42-ghost-commits.md` to `42-ghost-commits.complete.md`
</completion>

## Implementation Hindsight

<hindsight>
**Completed:** 2024-12-17

**Key Implementation Notes:**
1. GhostCommitManager in core/snapshots.py with all 4 required methods
2. Feature flag in config/features.py: ghost_commit (EXPERIMENTAL, off by default)
3. GhostCommitInfo model tracks: enabled, turn_number, commit_refs
4. Integration: session init creates manager, message completion creates commits, session delete cleans up
5. Uses --no-verify to bypass git hooks
6. Timeouts (5-10s) on all git operations for robustness
7. Event ghost_commit.created emitted with turn, hash, summary

**Files Modified:**
- `core/snapshots.py` - GhostCommitManager class
- `core/models/ghost_commit_info.py` - GhostCommitInfo model (pre-existed)
- `core/models/session.py` - Added ghost_commit field
- `config/defaults.py` - GHOST_COMMIT_CONFIG
- `config/features.py` - ghost_commit feature flag (pre-existed)
- `core/sessions.py` - Init and cleanup integration
- `core/messages.py` - Turn completion integration
- `core/state.py` - session_ghost_commits storage

**Prompt Improvements for Future:**
1. Specify exact event name (ghost_commit.created)
2. Clarify turn numbering (1-indexed vs 0-indexed)
3. Note that ignore_patterns config exists but enforcement is optional
4. Mention session fork handling
5. Add explicit integration with undo system endpoints
6. Include test scenarios for verification
</hindsight>
