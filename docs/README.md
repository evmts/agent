# Documentation

Comprehensive documentation for Plue architecture, infrastructure, and workflows.

## Purpose

Detailed technical documentation covering system design, deployment, migration guides, and product requirements. Complements the main README and code-level comments.

## Key Files

| File | Description |
|------|-------------|
| `architecture.md` | High-level system architecture overview |
| `infrastructure.md` | GKE deployment, Terraform, Helm, K8s configs |
| `migration.md` | Migration guide from previous architecture |
| `workflows-prd.md` | Product requirements for workflow system |
| `workflows-engineering.md` | Engineering design for workflows |
| `prd.md` | Overall product requirements document |
| `self-hosting.md` | Guide for self-hosting Plue |
| `logging.md` | Logging architecture and practices |
| `workflows/` | Workflow implementation milestones |

## Documentation Structure

```
docs/
├── architecture.md              # System design
├── infrastructure.md            # Deployment & infra
├── migration.md                 # Migration guide
├── workflows-prd.md             # Workflows product spec
├── workflows-engineering.md     # Workflows technical spec
├── prd.md                       # Product requirements
├── self-hosting.md              # Self-hosting guide
├── logging.md                   # Logging architecture
└── workflows/                   # Implementation milestones
    ├── 01-storage-foundations.md
    ├── 02-restrictedpython-runtime.md
    ├── 03-prompt-parser.md
    ├── 04-type-system-and-validation.md
    ├── 05-definition-discovery-and-registry.md
    ├── 06-execution-engine-shell.md
    ├── 07-llm-agent-tools-streaming.md
    ├── 08-runner-pool-and-sandbox.md
    ├── 09-api-cli-ui.md
    └── sandbox-config.md
```

## Reading Order

For new contributors:

1. `architecture.md` - Understand system design
2. `infrastructure.md` - Learn deployment model
3. `workflows-prd.md` - Understand workflow vision
4. `workflows-engineering.md` - Deep dive on implementation
5. `workflows/` - Milestone-by-milestone build plan

For deployers:

1. `infrastructure.md` - Full infrastructure guide
2. `self-hosting.md` - Self-hosting instructions
3. `logging.md` - Observability setup
