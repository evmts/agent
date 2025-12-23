"""
AI-powered code review workflow with multiple focus areas.

Each focus runs an independent review pass with tool access to explore
the codebase and gather context before making judgments.
"""

from plue import workflow, pull_request
from plue.prompts import CodeReview
from plue.tools import readfile, grep, glob, websearch


# Define review focus areas
FOCUSES = [
    {
        "name": "security",
        "description": "Security vulnerabilities and attack vectors",
        "checks": [
            "XSS and injection attacks",
            "Authentication/authorization flaws",
            "Secrets or credentials in code",
            "Unsafe deserialization",
            "CSRF vulnerabilities",
        ],
    },
    {
        "name": "performance",
        "description": "Performance issues and optimization opportunities",
        "checks": [
            "N+1 queries or unnecessary fetches",
            "Missing memoization or caching",
            "Bundle size impacts",
            "Unnecessary re-renders",
            "Memory leaks",
        ],
    },
    {
        "name": "correctness",
        "description": "Logic errors and potential bugs",
        "checks": [
            "Off-by-one errors",
            "Null/undefined handling",
            "Race conditions",
            "Error handling gaps",
            "Type mismatches",
        ],
    },
]


@workflow(
    triggers=[pull_request()],
    image="node:22-slim",
)
def review(ctx):
    """
    Multi-pass AI code review.

    Runs 3 independent review passes (security, performance, correctness),
    each with tool access to explore the repository.
    """

    diff = ctx.git.diff(base=ctx.event.pull_request.base)
    all_issues = []

    # Run each focused review pass
    for focus in FOCUSES:
        result = CodeReview(
            diff=diff,
            language="typescript",
            framework="nextjs",
            focus=focus["name"],
            focus_description=focus["description"],
            checks=focus["checks"],
            tools=[
                readfile(repo=ctx.repo, ref=ctx.event.pull_request.head),
                grep(repo=ctx.repo, ref=ctx.event.pull_request.head),
                glob(repo=ctx.repo, ref=ctx.event.pull_request.head),
                websearch(),
            ],
            max_turns=10,
        )

        all_issues.extend(result.issues)

    # Post summary comment
    if all_issues:
        summary = format_summary(all_issues)
        ctx.comment(summary)

        # Post inline comments for each issue
        for issue in all_issues:
            ctx.review_comment(
                path=issue.file,
                line=issue.line,
                body=f"**[{issue.focus}]** {issue.message}",
            )

    approved = not any(i.severity == "error" for i in all_issues)
    return ctx.success(approved=approved)


def format_summary(issues):
    """Format issues into a markdown summary."""
    by_focus = {}
    for issue in issues:
        by_focus.setdefault(issue.focus, []).append(issue)

    lines = ["## Code Review Summary\n"]

    for focus, focus_issues in by_focus.items():
        emoji = {"security": "🔒", "performance": "⚡", "correctness": "🐛"}
        lines.append(f"### {emoji.get(focus, '📋')} {focus.title()}\n")

        for issue in focus_issues:
            severity_icon = {"error": "❌", "warning": "⚠️", "suggestion": "💡"}
            icon = severity_icon.get(issue.severity, "•")
            lines.append(f"- {icon} `{issue.file}:{issue.line}` - {issue.message}")

        lines.append("")

    return "\n".join(lines)
