<prompt>
  <title>Runner Pool + Sandbox Enforcement</title>
  <objective>Implement runner registration, warm pool management, and container sandbox defaults.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Implement runner registration and heartbeat endpoints.</item>
    <item>Maintain a warm pool of runners and allocate jobs efficiently.</item>
    <item>Enforce container isolation defaults: gVisor, read-only rootfs, resource limits, network allowlist.</item>
    <item>Expose status for runner availability to the executor/queue.</item>
  </requirements>
  <deliverables>
    <item>Runner pool manager with registration + heartbeat logic.</item>
    <item>Runner selection strategy for workflow execution requests.</item>
    <item>Sandbox configuration wiring in runner startup.</item>
  </deliverables>
  <acceptance>
    <item>Runners register and are marked unhealthy when heartbeat expires.</item>
    <item>Queued workflows are assigned to available runners in FIFO order (or documented policy).</item>
    <item>Runtime containers apply isolation defaults from the PRD.</item>
  </acceptance>
  <out_of_scope>
    <item>UI or CLI features.</item>
    <item>Prompt parsing or plan generation.</item>
  </out_of_scope>
  <notes>
    <item>Keep sandbox settings configurable for future policies.</item>
    <item>Expose metrics/hooks for runner pool capacity.</item>
  </notes>
</prompt>

# Implementation Notes

- Prefer minimal, explicit configuration for resource limits and network policy.
- Document any runner lifecycle assumptions (startup time, cleanup, retries).
