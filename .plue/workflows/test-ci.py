from plue import workflow, push, pull_request

@workflow(
    triggers=[
        push(branches=["main"]),
        pull_request(types=["opened", "synchronize"]),
    ],
    image="ubuntu:22.04",
)
def ci(ctx):
    # Install dependencies
    ctx.run(name="install", cmd="bun install")

    # Run tests and lint
    ctx.run(name="test", cmd="bun test")
    ctx.run(name="lint", cmd="bun lint")

    # Build
    ctx.run(name="build", cmd="bun run build")

    return ctx.success()
