# Workflows Development Memory

This file tracks progress, learnings, and important context for the workflows implementation.

**IMPORTANT FOR AGENTS**:
- Read this file at the START of every session
- Update this file at the END of every session
- Do NOT trust prior claims without verification
- Add verified completions only after running tests yourself

---

## Session Log

<!-- New entries should be added at the top, above this comment -->

---

## Key Decisions

<!-- Architectural decisions, trade-offs, rationale -->

---

## Open Questions

<!-- Unresolved questions that need investigation or user input -->

---

## Validated Completions

<!-- Only add items here after personally verifying they work with tests -->

| Component | Status | Verified By | Date | Notes |
|-----------|--------|-------------|------|-------|

---

## Known Issues

<!-- Bugs, blockers, technical debt -->

---

## Implementation Checklist

Based on docs/workflows/ specs:

- [ ] 01 - Storage Foundations (schema, migrations)
- [ ] 02 - RestrictedPython Runtime (Zig evaluator)
- [ ] 03 - Prompt Parser (Jinja2 + YAML frontmatter)
- [ ] 04 - Type System and Validation
- [ ] 05 - Definition Discovery and Registry
- [ ] 06 - Execution Engine (shell steps)
- [ ] 07 - LLM/Agent Tools and Streaming
- [ ] 08 - Runner Pool and Sandbox
- [ ] 09 - API, CLI, and UI

---

## Testing Status

| Area | Unit Tests | Integration Tests | E2E Tests |
|------|------------|-------------------|-----------|
| Storage | - | - | - |
| Runtime | - | - | - |
| Parser | - | - | - |
| Types | - | - | - |
| Registry | - | - | - |
| Execution | - | - | - |
| LLM/Agent | - | - | - |
| Runner | - | - | - |
| API/CLI | - | - | - |
