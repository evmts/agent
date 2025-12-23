# ts-lib

Example TypeScript library using Zile and Plue workflows.

## Development

```bash
npm install
npm run dev      # Watch mode
npm run build    # Production build
npm test         # Run tests
```

## Plue Workflows

This project uses Plue instead of GitHub Actions. Workflows are defined in `.plue/workflow.py`:

- **ci**: Runs on push/PR - installs, tests, type-checks, and builds
- **review**: AI-powered code review for pull requests
