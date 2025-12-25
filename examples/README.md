# Examples

Example projects demonstrating Plue workflow integration.

## Purpose

Reference implementations showing how to integrate Plue workflows into different project types. Each example includes a complete `.plue/` directory with workflow definitions.

## Examples

| Directory | Description |
|-----------|-------------|
| `next-app/` | Next.js application with Plue workflows |
| `ts-lib/` | TypeScript library with Plue workflows |

## Structure

Each example follows this pattern:

```
example-name/
├── .plue/
│   ├── workflows/          # Workflow definitions (YAML)
│   └── tools/              # Custom Python tools
├── src/                    # Application code
├── package.json            # Dependencies
├── tsconfig.json           # TypeScript config
└── README.md               # Example-specific docs
```

## Usage

1. Clone example:
   ```bash
   cp -r examples/next-app my-project
   cd my-project
   ```

2. Install dependencies:
   ```bash
   pnpm install
   ```

3. Configure `.plue/workflows/*.yaml` for your needs

4. Push to Plue-hosted repository to trigger workflows

## Workflow Integration

Examples demonstrate:
- Workflow definitions in `.plue/workflows/`
- Custom tool implementations in `.plue/tools/`
- Trigger configuration (push, PR, manual)
- Context access (repo, commit, files)
- Result handling (status, artifacts)

See individual example READMEs for detailed usage.
