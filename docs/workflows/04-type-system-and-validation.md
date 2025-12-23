<prompt>
  <title>Type System + Plan Validation</title>
  <objective>Implement Starlark-like types and validate workflow plans, inputs, and outputs.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Implement type helpers: schema, enum, list, optional and their JSON Schema conversions.</item>
    <item>Validate workflow plans: DAG acyclicity, unique step IDs, known dependencies.</item>
    <item>Validate prompt inputs against input schema before rendering.</item>
    <item>Validate prompt outputs against output schema after LLM/agent completion.</item>
  </requirements>
  <deliverables>
    <item>Type system module shared by workflow runtime and prompt parser.</item>
    <item>Plan validator with structured error reporting (which step, why).</item>
    <item>Schema validation helpers for runtime inputs/outputs.</item>
  </deliverables>
  <acceptance>
    <item>Invalid plans (cycles, missing deps) fail fast with actionable errors.</item>
    <item>Prompt inputs that violate schema are rejected before execution.</item>
    <item>LLM outputs that violate schema are surfaced as step failures with details.</item>
  </acceptance>
  <out_of_scope>
    <item>Runner execution or streaming.</item>
    <item>UI integration.</item>
  </out_of_scope>
  <notes>
    <item>Follow the JSON Schema shapes shown in the engineering spec.</item>
    <item>Keep validation errors safe to display to end users (no secrets).</item>
  </notes>
</prompt>

# Implementation Notes

- Plan validation should run as part of workflow parse and before execution.
- Keep type conversion consistent across workflow DSL and prompt parser.
