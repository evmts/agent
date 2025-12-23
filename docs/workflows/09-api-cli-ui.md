<prompt>
  <title>API + CLI + UI Integration</title>
  <objective>Expose workflows via HTTP APIs, CLI commands, and frontend views with live streaming.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Implement workflow and prompt endpoints: parse, run, list runs, run detail, SSE stream, cancel.</item>
    <item>Wire CLI commands (list/run/view/watch/cancel, prompt preview/test, workflow lint).</item>
    <item>Build UI views for run list, run detail with DAG + logs, and agent view with tool calls.</item>
    <item>Ensure SSE events are consumed by UI with resilient reconnect behavior.</item>
  </requirements>
  <deliverables>
    <item>HTTP route handlers in Zig with request/response types and error handling.</item>
    <item>CLI subcommands that call the APIs (or direct service layer if local).</item>
    <item>Frontend pages/components for workflows, runs, and prompt editor.</item>
  </deliverables>
  <acceptance>
    <item>Can trigger a workflow run and watch live SSE updates in the UI.</item>
    <item>CLI can list runs and stream a live run.</item>
    <item>Prompt preview/test supports sample inputs and schema validation.</item>
  </acceptance>
  <out_of_scope>
    <item>Changes to runtime execution logic.</item>
    <item>Non-workflow UI areas.</item>
  </out_of_scope>
  <notes>
    <item>Match endpoint shapes from the engineering spec.</item>
    <item>Use GitHub Actions-like UX conventions from the PRD.</item>
  </notes>
</prompt>

# Implementation Notes

- Keep API error payloads consistent for CLI + UI reuse.
- Prioritize run list + run detail views before prompt editor polish.
