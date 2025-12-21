#!/usr/bin/env python3
"""
Automated Bug Fix Loop

This script automates the bug-fixing workflow:
1. Fetches open bugs from GitHub
2. Creates a handoff prompt for each bug
3. Spawns Claude Code session to fix the bug
4. Captures results and writes reports
5. Commits progress and continues to next bug

Usage:
    python scripts/bug-fix-loop.py [--dry-run] [--max-bugs N] [--start-issue N]

Requirements:
    pip install claude-agent-sdk
"""

import asyncio
import argparse
import json
import subprocess
import os
from datetime import datetime
from pathlib import Path
from typing import Optional, AsyncIterator
from dataclasses import dataclass, field

# SDK imports - will fail gracefully if not installed
try:
    from claude_agent_sdk import query, ClaudeAgentOptions
    SDK_AVAILABLE = True
except ImportError:
    SDK_AVAILABLE = False
    print("Warning: claude-agent-sdk not installed. Run: pip install claude-agent-sdk")


@dataclass
class BugInfo:
    """Information about a bug from GitHub issues."""
    number: int
    title: str
    body: str
    labels: list[str]
    test_file: Optional[str] = None
    test_line: Optional[int] = None
    priority: str = "Medium"


@dataclass
class FixResult:
    """Result of a bug fix attempt."""
    bug: BugInfo
    success: bool
    commit_hash: Optional[str] = None
    error_message: Optional[str] = None
    duration_seconds: float = 0
    cost_usd: float = 0
    logs: list[str] = field(default_factory=list)


# Bug priority ordering
PRIORITY_ORDER = {
    "Critical": 0,
    "High": 1,
    "Medium": 2,
    "Low": 3
}

# Known bugs with their test locations
KNOWN_BUGS = {
    38: {"test_file": "e2e/bugs.spec.ts", "test_line": 336, "priority": "High"},
    37: {"test_file": "e2e/bugs.spec.ts", "test_line": 284, "priority": "High"},
    36: {"test_file": "e2e/bugs.spec.ts", "test_line": 217, "priority": "Medium"},
    34: {"test_file": "e2e/bugs.spec.ts", "test_line": 12, "priority": "Medium"},
    39: {"test_file": "e2e/bugs.spec.ts", "test_line": 430, "priority": "Medium"},
    35: {"test_file": "e2e/bugs.spec.ts", "test_line": 99, "priority": "Low"},
    41: {"test_file": "e2e/bugs-2025-12-20.spec.ts", "test_line": 120, "priority": "High"},
    40: {"test_file": "e2e/bugs.spec.ts", "test_line": 506, "priority": "Critical"},
}


def run_command(cmd: str) -> tuple[int, str, str]:
    """Run a shell command and return (returncode, stdout, stderr)."""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def get_open_bugs() -> list[BugInfo]:
    """Fetch open bugs from GitHub issues."""
    code, stdout, stderr = run_command(
        'gh issue list --state open --label bug --json number,title,body,labels'
    )

    if code != 0:
        print(f"Error fetching issues: {stderr}")
        return []

    try:
        issues = json.loads(stdout)
    except json.JSONDecodeError:
        print(f"Error parsing issues JSON: {stdout}")
        return []

    bugs = []
    for issue in issues:
        bug_info = KNOWN_BUGS.get(issue["number"], {})
        labels = [l["name"] for l in issue.get("labels", [])]

        bugs.append(BugInfo(
            number=issue["number"],
            title=issue["title"],
            body=issue.get("body", ""),
            labels=labels,
            test_file=bug_info.get("test_file"),
            test_line=bug_info.get("test_line"),
            priority=bug_info.get("priority", "Medium")
        ))

    # Sort by priority
    bugs.sort(key=lambda b: PRIORITY_ORDER.get(b.priority, 99))
    return bugs


def create_handoff_prompt(bug: BugInfo) -> str:
    """Create a detailed handoff prompt for the bug fix agent."""

    test_info = ""
    if bug.test_file and bug.test_line:
        test_info = f"""
## Test Location
- **File**: `{bug.test_file}:{bug.test_line}`
- **Run test**: `bun playwright test -g "BUG-{bug.number:03d}" --reporter=list`
"""

    return f'''# Bug Fix Agent Handoff Prompt

## Your Task
Fix GitHub Issue #{bug.number}: {bug.title}

This is a **{bug.priority}** priority bug. Follow the /bug-fix workflow.

---

## Current State

| Item          | Value                               |
|---------------|-------------------------------------|
| Git Branch    | plue-git (single-branch workflow)   |
| Services      | Docker containers should be running |

```bash
# Verify state
git branch -vv
docker-compose ps
```

---

## Critical Rules

1. **SINGLE-BRANCH WORKFLOW**: Work directly on `plue-git`. Do NOT create feature branches.
2. **Commit directly**: `git commit` then `git push origin plue-git`
3. **Test-driven**: Verify fix with Playwright tests
4. **Update GitHub**: Comment on issue #{bug.number} with results, close if fixed

---

## Issue #{bug.number} Details

**Title**: {bug.title}
**Priority**: {bug.priority}

**Description**:
{bug.body or "No description provided."}
{test_info}

---

## Workflow Checklist

```bash
# Phase 1: Analyze
gh issue view {bug.number} --json body
bun playwright test -g "BUG-{bug.number:03d}" --reporter=list  # See current failure

# Phase 2: Investigate
# Read affected files, understand the bug

# Phase 3: Fix
# Implement the minimal fix

# Phase 4: Verify
bun playwright test -g "BUG-{bug.number:03d}"  # Must pass
bun playwright test e2e/bugs*.spec.ts          # No regressions

# Phase 5: Commit & Close
git add -A
git commit -m "fix: [description]

Fixes #{bug.number}"

git push origin plue-git
gh issue close {bug.number} --reason completed
```

---

## Gotchas from Previous Fixes

1. **Auth endpoint**: `/api/auth/siwe/verify`, not `/api/auth/login`
2. **Rebuild after Zig changes**: `zig build server` or rebuild Docker
3. **JSON escaping**: Playwright sends `\\u0000` not raw null bytes
4. **Route patterns**: Issues are at `/api/:user/:repo/issues` (no `/repos/` prefix)
5. **Single-branch**: Commit directly to `plue-git`, no feature branches

---

## Important

After fixing the bug:
1. Write a brief summary of what you changed
2. Include the commit hash
3. Confirm tests pass
'''


def write_report(result: FixResult, reports_dir: Path) -> Path:
    """Write a fix report to the reports directory."""
    reports_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    report_file = reports_dir / f"bug-{result.bug.number}-{timestamp}.md"

    status = "SUCCESS" if result.success else "FAILED"

    report = f"""# Bug Fix Report: Issue #{result.bug.number}

**Status**: {status}
**Date**: {datetime.now().isoformat()}
**Duration**: {result.duration_seconds:.1f}s
**Cost**: ${result.cost_usd:.4f}

## Bug Details
- **Title**: {result.bug.title}
- **Priority**: {result.bug.priority}
- **Labels**: {', '.join(result.bug.labels) or 'None'}

## Result
"""

    if result.success:
        report += f"""
### Commit
`{result.commit_hash or 'Unknown'}`

### Summary
Bug was successfully fixed and tests pass.
"""
    else:
        report += f"""
### Error
{result.error_message or 'Unknown error'}

### Logs
```
{chr(10).join(result.logs[-50:])}  # Last 50 log lines
```
"""

    report_file.write_text(report)
    return report_file


async def fix_bug_with_sdk(bug: BugInfo, dry_run: bool = False) -> FixResult:
    """Use Claude Agent SDK to fix a bug."""
    if not SDK_AVAILABLE:
        return FixResult(
            bug=bug,
            success=False,
            error_message="Claude Agent SDK not installed"
        )

    start_time = datetime.now()
    logs = []
    total_cost = 0

    prompt = create_handoff_prompt(bug)

    if dry_run:
        print(f"\n{'='*60}")
        print(f"DRY RUN: Would fix bug #{bug.number}")
        print(f"{'='*60}")
        print(prompt[:500] + "...")
        return FixResult(
            bug=bug,
            success=True,
            error_message="Dry run - no changes made"
        )

    try:
        options = ClaudeAgentOptions(
            allowed_tools=[
                "Read", "Write", "Edit", "Glob", "Grep",
                "Bash", "Task", "TodoWrite"
            ],
            permission_mode="acceptEdits",
            max_turns=50,
        )

        print(f"\n{'='*60}")
        print(f"Starting fix for bug #{bug.number}: {bug.title}")
        print(f"{'='*60}")

        async for message in query(prompt=prompt, options=options):
            # Log assistant messages
            if hasattr(message, 'message') and message.message:
                for block in message.message.content:
                    if hasattr(block, 'text'):
                        logs.append(block.text)
                        print(block.text[:200])  # Print first 200 chars

            # Capture result metadata
            if hasattr(message, 'total_cost_usd'):
                total_cost = message.total_cost_usd

        # Check if fix was successful by looking for commit
        code, stdout, _ = run_command('git log -1 --format="%H %s"')
        commit_hash = stdout.split()[0] if stdout else None

        # Check if tests pass
        code, _, _ = run_command(f'bun playwright test -g "BUG-{bug.number:03d}" --reporter=list')
        tests_pass = code == 0

        duration = (datetime.now() - start_time).total_seconds()

        return FixResult(
            bug=bug,
            success=tests_pass,
            commit_hash=commit_hash,
            duration_seconds=duration,
            cost_usd=total_cost,
            logs=logs
        )

    except Exception as e:
        return FixResult(
            bug=bug,
            success=False,
            error_message=str(e),
            duration_seconds=(datetime.now() - start_time).total_seconds(),
            logs=logs
        )


def commit_report(report_path: Path) -> bool:
    """Commit a report file."""
    code, _, stderr = run_command(f'git add {report_path}')
    if code != 0:
        print(f"Error staging report: {stderr}")
        return False

    code, _, stderr = run_command(
        f'git commit -m "docs: Add bug fix report for {report_path.stem}"'
    )
    if code != 0:
        print(f"Error committing report: {stderr}")
        return False

    return True


async def main():
    parser = argparse.ArgumentParser(description="Automated Bug Fix Loop")
    parser.add_argument("--dry-run", action="store_true", help="Don't make changes")
    parser.add_argument("--max-bugs", type=int, default=5, help="Max bugs to fix")
    parser.add_argument("--start-issue", type=int, help="Start with specific issue")
    parser.add_argument("--reports-dir", type=str, default="reports/bug-fixes",
                        help="Directory for fix reports")
    args = parser.parse_args()

    reports_dir = Path(args.reports_dir)

    print("Fetching open bugs from GitHub...")
    bugs = get_open_bugs()

    if not bugs:
        print("No open bugs found!")
        return

    print(f"Found {len(bugs)} open bugs:")
    for bug in bugs:
        print(f"  #{bug.number} [{bug.priority}] {bug.title}")

    # Filter to specific issue if requested
    if args.start_issue:
        bugs = [b for b in bugs if b.number >= args.start_issue]

    # Limit number of bugs
    bugs = bugs[:args.max_bugs]

    results = []

    for i, bug in enumerate(bugs, 1):
        print(f"\n{'#'*60}")
        print(f"# Bug {i}/{len(bugs)}: Issue #{bug.number}")
        print(f"{'#'*60}")

        result = await fix_bug_with_sdk(bug, dry_run=args.dry_run)
        results.append(result)

        # Write report
        if not args.dry_run:
            report_path = write_report(result, reports_dir)
            print(f"Report written: {report_path}")

            # Commit report
            if commit_report(report_path):
                print("Report committed")

        # Stop on failure (optional - could continue)
        if not result.success and not args.dry_run:
            print(f"\nBug #{bug.number} fix failed. Stopping loop.")
            break

    # Print summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")

    successful = sum(1 for r in results if r.success)
    total_cost = sum(r.cost_usd for r in results)
    total_time = sum(r.duration_seconds for r in results)

    print(f"Bugs attempted: {len(results)}")
    print(f"Successful: {successful}")
    print(f"Failed: {len(results) - successful}")
    print(f"Total time: {total_time:.1f}s")
    print(f"Total cost: ${total_cost:.4f}")

    for result in results:
        status = "✓" if result.success else "✗"
        print(f"  {status} #{result.bug.number}: {result.bug.title}")


if __name__ == "__main__":
    asyncio.run(main())
