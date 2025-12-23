"""
CI workflow for ts-lib TypeScript library.

This workflow runs on every push and PR to validate the library.
"""

from plue import workflow, push, pull_request, cache_key, hash_files
from plue.prompts import CodeReview


@workflow(
    triggers=[
        push(branches=["main"]),
        pull_request(),
    ],
    image="node:22-slim",
)
def ci(ctx):
    """Build, test, and type-check the TypeScript library."""

    # Install dependencies with caching
    install = ctx.run(
        name="install",
        cmd="npm install",
        cache=cache_key("node-deps", hash_files("package-lock.json")),
    )

    # Run tests
    test = ctx.run(
        name="test",
        cmd="npm test",
        needs=[install],
    )

    # Type-check
    typecheck = ctx.run(
        name="typecheck",
        cmd="npm run typecheck",
        needs=[install],
    )

    # Build
    build = ctx.run(
        name="build",
        cmd="npm run build",
        needs=[install, typecheck],
    )

    return ctx.success(
        outputs={
            "test_passed": test.success,
            "build_passed": build.success,
        }
    )


@workflow(
    triggers=[pull_request()],
    image="node:22-slim",
)
def review(ctx):
    """AI-powered code review for pull requests."""

    # Get the diff
    diff = ctx.git.diff(base=ctx.event.pull_request.base)

    # Run code review
    review = CodeReview(
        diff=diff,
        language="typescript",
        guidelines=ctx.read("CONTRIBUTING.md", optional=True),
    )

    if review.has_issues:
        ctx.comment(review.summary)

        for issue in review.issues:
            ctx.review_comment(
                path=issue.file,
                line=issue.line,
                body=issue.message,
            )

    return ctx.success(approved=review.approved)
