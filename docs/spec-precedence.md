# Spec Precedence & Conflict Resolution

When specs conflict, the higher-precedence rule wins. Agent or implementer MUST note the conflict and which rule took precedence.

## Precedence (highest first)

1. **Always Green** — Build/tests passing. Nothing ships broken.
2. **Architecture invariants** — Zig source of truth, dependency injection, 5 interfaces, libghostty pattern.
3. **Language rules** — `zig-rules.md`, `swift-rules.md`, `ghostty-patterns.md`. Correct API usage, memory safety.
4. **Current ticket** — What the task actually requires. Ticket scope overrides general guidance.
5. **Engineering spec** — Implementation approach, data flow, module boundaries.
6. **Design spec** — UI/UX, tokens, layout, interactions.
7. **Style guidance** — "Minimal comments", "elegant code", "DRY". Lowest priority — never block shipping.

## Rules

- If two docs disagree on the same topic, the one listed as **canonical** in `spec-index.md` wins.
- If a conflict is detected during implementation, explicitly note it in the ticket output (plan, implement, or review) and pick the higher-precedence rule.
- Dependent docs MUST reference the canonical doc and not redefine its rules. If they add context, they must not contradict.
- When in doubt: ask "does this break the build?" (precedence 1), "does this violate architecture?" (precedence 2), "does this use wrong API?" (precedence 3). If none apply, use judgment.
