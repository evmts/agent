# Workflow Implementation Milestones

Step-by-step implementation plan for the Plue workflow system.

## Purpose

Breaks down the workflow system implementation into discrete, testable milestones. Each file represents one phase of development with clear deliverables and acceptance criteria.

## Milestones

| File | Milestone | Status |
|------|-----------|--------|
| `01-storage-foundations.md` | Database schema and DAOs | Complete |
| `02-restrictedpython-runtime.md` | RestrictedPython sandbox | Complete |
| `03-prompt-parser.md` | YAML prompt parser (Rust) | Complete |
| `04-type-system-and-validation.md` | Type system and validation | Complete |
| `05-definition-discovery-and-registry.md` | Workflow discovery | Complete |
| `06-execution-engine-shell.md` | Execution engine core | Complete |
| `07-llm-agent-tools-streaming.md` | LLM integration + streaming | Complete |
| `08-runner-pool-and-sandbox.md` | K8s runner pool + gVisor | Complete |
| `09-api-cli-ui.md` | API, CLI, UI | Complete |
| `sandbox-config.md` | gVisor sandbox configuration | Reference |

## Implementation Approach

Each milestone follows this structure:

```markdown
# Milestone N: Title

## Goal
What this milestone achieves

## Deliverables
- Concrete outputs
- Testable features
- Documentation

## Acceptance Criteria
How to verify completion

## Implementation Notes
Technical details and decisions
```

## Dependencies

Milestones build on each other:

```
01 (Storage) → 02 (Runtime) → 03 (Parser)
                                    ↓
04 (Types) → 05 (Discovery) → 06 (Execution)
                                    ↓
                07 (LLM) → 08 (Pool) → 09 (API/UI)
```

Start at milestone 01 and work sequentially through 09.

## Current State

All core milestones (01-09) are complete. The workflow system is fully functional with:
- YAML-based workflow definitions
- RestrictedPython for safe user code execution
- Claude API integration with streaming
- K8s-based runner pool with gVisor sandboxing
- Full API, CLI, and UI support
