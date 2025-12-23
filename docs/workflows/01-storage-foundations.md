<prompt>
  <title>Workflow Storage Foundations</title>
  <objective>Land the database schema and persistence plumbing that all workflow parsing/execution layers build upon.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Add SQL migration(s) for workflow and prompt definitions, runs, steps, logs, and LLM usage (align with spec).</item>
    <item>Expose minimal data-access helpers for CRUD of workflow_definitions, prompt_definitions, workflow_runs, workflow_steps, workflow_logs, llm_usage.</item>
    <item>Store content hashes and parsed_at timestamps on definitions for cache invalidation.</item>
    <item>Keep schema compatible with existing repository_id references and timestamp conventions.</item>
  </requirements>
  <deliverables>
    <item>New migration file(s) with the tables and indexes defined in the engineering spec.</item>
    <item>DB access layer updates to read/write workflow + prompt definitions, create runs, and append logs.</item>
    <item>Lightweight seed/fixture or inline test data helpers if the project already uses them.</item>
  </deliverables>
  <acceptance>
    <item>Migration applies cleanly on a fresh database.</item>
    <item>Can create a workflow definition, prompt definition, and run record, then query them back by repository_id + name.</item>
    <item>Logs append in order with sequence numbers per step.</item>
  </acceptance>
  <out_of_scope>
    <item>Parsing workflow files or executing steps.</item>
    <item>UI changes or API endpoints.</item>
  </out_of_scope>
  <notes>
    <item>Prefer additive migrations; do not modify unrelated tables.</item>
    <item>Follow existing database conventions for JSONB, indexes, and timestamps.</item>
  </notes>
</prompt>

# Implementation Notes

- Use the schema in `docs/workflows-engineering.md` as the source of truth.
- Ensure any indices on run status and step ordering match expected query patterns (run list, step log streaming).
- Keep output JSONB fields flexible for future schema evolution.
