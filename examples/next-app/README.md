# next-app

Example Next.js application using Plue workflows.

## Getting Started

```bash
pnpm install
pnpm dev         # Development server at localhost:3000
pnpm build       # Production build
pnpm lint        # Lint code
```

## Plue Workflows

This project uses Plue instead of GitHub Actions. Workflows are defined in `.plue/workflow.py`:

- **ci**: Runs on push/PR - installs, lints, type-checks, and builds
- **preview**: Deploys preview and generates AI summary for PRs
- **review**: AI-powered code review for pull requests

## Learn More

- [Next.js Documentation](https://nextjs.org/docs)
- [Plue Workflows](https://plue.dev/docs/workflows)
