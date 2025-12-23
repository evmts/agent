<prompt>
  <title>RestrictedPython Workflow Runtime</title>
  <objective>Implement the sandboxed plan-generation runtime that evaluates workflow .py files into deterministic plans.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Embed a RestrictedPython-compatible evaluator in the Zig service (RustPython via FFI or custom AST evaluator).</item>
    <item>Implement Plue builtins: workflow decorator, triggers, ctx object, step primitives, and type helpers.</item>
    <item>Ensure plan generation is deterministic and performs no I/O, network calls, or system access.</item>
    <item>Capture and return plan DAG with step metadata (id, name, type, config, depends_on).</item>
    <item>Enforce the blocked Python features from the PRD (imports beyond allowlist, eval, exec, etc.).</item>
  </requirements>
  <deliverables>
    <item>Zig runtime module that loads .plue/workflows/*.py, evaluates in restricted globals, and extracts workflow definitions.</item>
    <item>Plue builtins implementation with workflow/trigger helpers and ctx.run/ctx.parallel primitives.</item>
    <item>Deterministic plan output format aligned with the engineering spec.</item>
  </deliverables>
  <acceptance>
    <item>Given a simple workflow file, runtime returns a plan with stable step IDs and dependencies.</item>
    <item>Forbidden operations (import, open, socket, exec, etc.) fail with clear errors.</item>
    <item>Multiple workflows in a file register independently with unique names.</item>
  </acceptance>
  <out_of_scope>
    <item>Prompt parsing or LLM execution.</item>
    <item>Persisting workflow definitions to the database (handled in a later phase).</item>
  </out_of_scope>
  <notes>
    <item>Adopt the builtins reference shapes from `docs/workflows-engineering.md` for parity.</item>
    <item>Return placeholder strings for ctx.read/ctx.secret/hash_files to be resolved at execution time.</item>
  </notes>
</prompt>

# Implementation Notes

- Keep the restricted globals small and explicit. Only expose `plue` builtins and primitives required by the workflow DSL.
- Preserve the plan-only semantics: workflow code registers steps but never executes them directly.
- Ensure the runtime can surface parse errors with file and line context for developer ergonomics.
