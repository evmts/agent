<prompt>
  <title>Execution Engine Core + Shell Steps</title>
  <objective>Build the DAG executor that runs shell steps (and parallel groups) and reports status/logs.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Topologically sort and execute workflow plans with dependency tracking.</item>
    <item>Support parallel step groups with configurable concurrency limits.</item>
    <item>Execute shell steps inside the runner container and capture stdout/stderr streaming.</item>
    <item>Persist step status transitions, exit codes, and outputs to the database.</item>
    <item>Emit streaming events compatible with SSE protocol.</item>
  </requirements>
  <deliverables>
    <item>DAG execution module in the Zig service (or runner) with step state machine.</item>
    <item>Shell step executor with timeouts, env injection, and cache key metadata.</item>
    <item>Log streaming hooks that append workflow_logs rows and emit events.</item>
  </deliverables>
  <acceptance>
    <item>Plan with dependencies runs in correct order; parallel steps execute concurrently.</item>
    <item>Step logs are streamed and stored in order.</item>
    <item>Failures mark dependent steps as skipped or blocked, with clear errors.</item>
  </acceptance>
  <out_of_scope>
    <item>LLM or agent steps.</item>
    <item>Runner pool orchestration.</item>
  </out_of_scope>
  <notes>
    <item>Match step event types and payloads in the streaming protocol spec.</item>
    <item>Use container sandboxing defaults from the PRD.</item>
  </notes>
</prompt>

# Implementation Notes

- Store step outputs in JSONB so downstream steps can read them.
- Ensure step status transitions are atomic to avoid inconsistent UI states.
