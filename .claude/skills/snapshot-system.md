# Snapshot System

This skill covers the Git-based file state tracking system that enables reverting changes made by agents.

## Overview

The snapshot system captures and restores filesystem state using Git tree objects (not commits) for lightweight state tracking. This enables reverting agent changes to any previous point in a session.

## Key Files

| File | Purpose |
|------|---------|
| `snapshot/snapshot.py` | Core Snapshot class |
| `core/snapshots.py` | Session-level helpers |
| `core/messages.py` | Snapshot integration in messaging |

## Architecture

```
Session Start
    │
    └── init_snapshot(session_id, project_dir)
            │
            └── Snapshot instance created
                    │
                    └── .agent/snapshots/ (bare git repo)

Message Processing
    │
    ├── Before: track_snapshot() → tree SHA (before_hash)
    │
    ├── Agent executes tools (file changes)
    │
    └── After: track_snapshot() → tree SHA (after_hash)
            │
            └── compute_diff(before_hash, after_hash)

Revert
    │
    └── snapshot.revert(hash, files)
```

## Storage Location

```
project_dir/
└── .agent/
    └── snapshots/      # Bare git repository
        ├── HEAD
        ├── objects/    # Git tree objects
        ├── info/
        │   └── exclude # Ignores .agent/ itself
        └── refs/
```

## Snapshot Class

### Initialization

```python
from snapshot.snapshot import Snapshot

# Create snapshot system for a project
snap = Snapshot(project_dir="/path/to/project")

# Repository is lazily initialized on first operation
```

### Core Operations

#### track() - Capture State

```python
# Capture current filesystem state
tree_sha = snap.track()
# Returns: "a1b2c3d4e5f6..." (40-char hex SHA)
```

Creates a Git tree object representing all files in the project directory.

#### patch() - List Changed Files

```python
# Compare snapshot to current working tree
changed_files = snap.patch(from_hash)
# Returns: ["src/main.py", "README.md", ...]

# Compare two snapshots
changed_files = snap.patch(from_hash, to_hash)
```

#### revert() - Restore Specific Files

```python
# Restore specific files from a snapshot
snap.revert(hash="a1b2c3d4...", files=["src/main.py", "config.yaml"])
```

#### restore() - Full Restoration

```python
# Restore all files to snapshot state
snap.restore(hash="a1b2c3d4...")
```

#### diff_full() - Detailed Diff

```python
from core.models.file_diff import FileDiff

diffs: list[FileDiff] = snap.diff_full(from_hash, to_hash)

for diff in diffs:
    print(f"File: {diff.file}")
    print(f"  Additions: {diff.additions}")
    print(f"  Deletions: {diff.deletions}")
    print(f"  Before: {diff.before[:100]}...")
    print(f"  After: {diff.after[:100]}...")
```

### Helper Methods

```python
# Get file contents at a snapshot
content = snap.get_file_at(hash, "path/to/file.py")

# List all files in a snapshot
files = snap.list_files(hash)

# Check if file exists in snapshot
exists = snap.file_exists_at(hash, "path/to/file.py")
```

## Git Operations

The snapshot system uses Git's tree objects without creating commits:

```python
# Environment setup for git operations
with repo.git.custom_environment(
    GIT_DIR=str(self.snapshot_dir),
    GIT_WORK_TREE=str(self.project_dir)
):
    # Stage all files
    repo.git.add("-A")

    # Create tree object (no commit)
    tree_sha = repo.git.write_tree()

    # For reverting: read tree into index
    repo.git.read_tree(hash)

    # Checkout files from index
    repo.git.checkout_index("-f", "--", *files)
```

## Session Integration

### Session Helpers

In `core/snapshots.py`:

```python
# Session-scoped snapshot instances
_snapshots: dict[str, Snapshot] = {}
_snapshot_history: dict[str, list[str]] = {}

def init_snapshot(session_id: str, project_dir: str) -> None:
    """Initialize snapshot for a session."""
    _snapshots[session_id] = Snapshot(project_dir)
    _snapshot_history[session_id] = []

def track_snapshot(session_id: str) -> str:
    """Track current state and add to history."""
    snapshot = _snapshots[session_id]
    hash = snapshot.track()
    _snapshot_history[session_id].append(hash)
    return hash

def compute_diff(session_id: str, from_hash: str, to_hash: str) -> list[FileDiff]:
    """Compute detailed diff between two snapshots."""
    snapshot = _snapshots[session_id]
    return snapshot.diff_full(from_hash, to_hash)
```

### Message Flow Integration

In `core/messages.py`:

```python
async def send_message(session_id: str, ...):
    # Track state before agent runs
    before_hash = track_snapshot(session_id)

    # Run agent (may modify files)
    async for event in agent.run(...):
        yield event

    # Track state after agent completes
    after_hash = track_snapshot(session_id)

    # Compute and store diff
    if before_hash != after_hash:
        diffs = compute_diff(session_id, before_hash, after_hash)
        # Store in session for revert capability
```

## API Endpoints

### GET /session/{id}/diff

Get file changes in a session:

```json
{
  "diffs": [
    {
      "file": "src/main.py",
      "before": "original content...",
      "after": "modified content...",
      "additions": 15,
      "deletions": 3
    }
  ]
}
```

### POST /session/{id}/revert

Revert to a specific message:

```json
{
  "messageID": "msg_123",
  "partID": "part_456"  // optional
}
```

### POST /session/{id}/unrevert

Undo a revert:

```json
{}
```

## Data Models

### FileDiff

```python
from pydantic import BaseModel

class FileDiff(BaseModel):
    file: str       # Relative path
    before: str     # Content before change
    after: str      # Content after change
    additions: int  # Lines added
    deletions: int  # Lines deleted
```

### RevertInfo

```python
class RevertInfo(BaseModel):
    messageID: str
    partID: str | None = None
    snapshot: str | None = None  # Tree SHA
    diff: str | None = None
```

## Best Practices

1. **Initialize early**: Call `init_snapshot()` when session is created
2. **Track frequently**: Track before and after agent operations
3. **Store history**: Keep snapshot hashes for each message
4. **Handle errors**: Git operations can fail on large files or permissions

## Edge Cases

### Binary Files

```python
# numstat shows "-" for binary files
adds_str, dels_str, filepath = parts
adds = 0 if adds_str == "-" else int(adds_str)
dels = 0 if dels_str == "-" else int(dels_str)
```

### File Encoding

```python
# May fail on binary or non-UTF-8 files
try:
    after = filepath_abs.read_text()
except Exception:
    after = ""  # Binary or unreadable
```

### Excluded Directories

The `.agent/` directory is excluded from snapshots via `info/exclude`:

```
# .agent/snapshots/info/exclude
.agent/
```

## Testing

```python
import pytest
from snapshot.snapshot import Snapshot

@pytest.fixture
def temp_project(tmp_path):
    """Create temp project with git initialized."""
    import subprocess
    subprocess.run(["git", "init"], cwd=tmp_path)
    return tmp_path

def test_track_and_revert(temp_project):
    snap = Snapshot(str(temp_project))

    # Create file and track
    (temp_project / "test.txt").write_text("original")
    hash1 = snap.track()

    # Modify file and track
    (temp_project / "test.txt").write_text("modified")
    hash2 = snap.track()

    # Revert to original
    snap.revert(hash1, ["test.txt"])

    assert (temp_project / "test.txt").read_text() == "original"
```

## Related Skills

- [api-development.md](./api-development.md) - Revert/diff endpoints
- [testing.md](./testing.md) - E2E test fixtures with git init
