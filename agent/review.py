"""
Code review functionality with structured prompts and parsing.

Provides AI-powered code review on git diffs with severity classification.
"""

import re
from typing import Optional

# =============================================================================
# Review Prompt Template
# =============================================================================

REVIEW_PROMPT = """You are a code reviewer. Analyze the following code changes and provide a structured review.

## Code Changes (Git Diff)
```diff
{diff}
```

## Review Guidelines
1. **Critical Issues**: Security vulnerabilities, bugs, crashes
2. **Warnings**: Potential issues, edge cases, performance
3. **Suggestions**: Code quality, readability, best practices
4. **Positive Notes**: Good patterns and practices observed

## Output Format
Provide your review in this format:

### Critical Issues
- [File:Line] Description of issue

### Warnings
- [File:Line] Description of warning

### Suggestions
- [File:Line] Suggestion for improvement

### Positive Notes
- Notable good practices or patterns

### Summary
Brief summary of the review (1-2 sentences).

If no changes to review, respond with "No changes to review."
"""


# =============================================================================
# Output Parsing
# =============================================================================


class ReviewIssue:
    """A single review issue."""

    def __init__(
        self,
        severity: str,
        file: str,
        line: Optional[int],
        message: str,
    ):
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message

    def to_dict(self):
        """Convert to dictionary representation."""
        return {
            "severity": self.severity,
            "file": self.file,
            "line": self.line,
            "message": self.message,
        }


class ReviewResult:
    """Structured review result."""

    def __init__(
        self,
        issues: list[ReviewIssue],
        positive_notes: list[str],
        summary: str,
    ):
        self.issues = issues
        self.positive_notes = positive_notes
        self.summary = summary

    def to_dict(self):
        """Convert to dictionary representation."""
        return {
            "issues": [issue.to_dict() for issue in self.issues],
            "positive_notes": self.positive_notes,
            "summary": self.summary,
        }

    def has_critical_issues(self) -> bool:
        """Check if there are any critical issues."""
        return any(issue.severity == "critical" for issue in self.issues)

    def has_warnings(self) -> bool:
        """Check if there are any warnings."""
        return any(issue.severity == "warning" for issue in self.issues)


def parse_review_output(content: str) -> ReviewResult:
    """
    Parse structured review output from the LLM.

    Args:
        content: Raw LLM output text

    Returns:
        ReviewResult with parsed issues and notes
    """
    issues = []
    positive_notes = []
    summary = ""

    # Split into sections
    lines = content.split("\n")
    current_section = None

    # Pattern to match: [File:Line] Message or [File] Message
    issue_pattern = re.compile(r"^\s*-\s*\[([^:]+):?(\d+)?\]\s*(.+)$")

    for line in lines:
        line = line.strip()

        # Detect sections
        if "### Critical Issues" in line or "Critical Issues" in line:
            current_section = "critical"
            continue
        elif "### Warnings" in line or "Warnings" in line:
            current_section = "warning"
            continue
        elif "### Suggestions" in line or "Suggestions" in line:
            current_section = "suggestion"
            continue
        elif "### Positive Notes" in line or "Positive Notes" in line:
            current_section = "positive"
            continue
        elif "### Summary" in line or "Summary" in line:
            current_section = "summary"
            continue

        # Parse content based on section
        if not line or line.startswith("#"):
            continue

        if current_section in ["critical", "warning", "suggestion"]:
            match = issue_pattern.match(line)
            if match:
                file = match.group(1).strip()
                line_num = int(match.group(2)) if match.group(2) else None
                message = match.group(3).strip()

                issues.append(
                    ReviewIssue(
                        severity=current_section,
                        file=file,
                        line=line_num,
                        message=message,
                    )
                )
            elif line.startswith("-"):
                # Fallback for items without file:line format
                message = line[1:].strip()
                issues.append(
                    ReviewIssue(
                        severity=current_section,
                        file="",
                        line=None,
                        message=message,
                    )
                )

        elif current_section == "positive":
            if line.startswith("-"):
                positive_notes.append(line[1:].strip())
            elif line and not line.startswith("#"):
                positive_notes.append(line)

        elif current_section == "summary":
            if line and not line.startswith("#"):
                if summary:
                    summary += " " + line
                else:
                    summary = line

    return ReviewResult(
        issues=issues,
        positive_notes=positive_notes,
        summary=summary.strip() or "No summary provided.",
    )
