<prompt>
  <title>Definition Discovery + Registry</title>
  <objective>Scan repo files, parse workflow/prompt definitions, and persist them for execution.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Discover `.plue/workflows/*.py` and `.plue/prompts/*.prompt.md` (and tool paths) for a repository.</item>
    <item>Run the RestrictedPython evaluator to produce workflow plans, then validate and store them.</item>
    <item>Parse prompt definitions, validate schemas, and store compiled metadata.</item>
    <item>Implement content hashing to avoid re-parsing unchanged files.</item>
    <item>Auto-import prompt definitions into `plue.prompts` namespace for workflow usage.</item>
  </requirements>
  <deliverables>
    <item>Workflow/prompt discovery service or CLI command used by parse endpoint.</item>
    <item>Database persistence for workflow_definitions and prompt_definitions.</item>
    <item>Import mechanism that makes prompts callable in workflow DSL.</item>
  </deliverables>
  <acceptance>
    <item>Updating a workflow or prompt file updates its stored definition; unchanged files are skipped.</item>
    <item>Workflow files can reference prompts by name via `from plue.prompts import ...`.</item>
    <item>Parse errors include file paths and allow partial success (other definitions still load).</item>
  </acceptance>
  <out_of_scope>
    <item>Execution engine or runner integration.</item>
    <item>UI display of definitions.</item>
  </out_of_scope>
  <notes>
    <item>Follow the prompt auto-import flow from the engineering spec.</item>
    <item>Respect repo-relative paths and git ref semantics if the codebase already has them.</item>
  </notes>
</prompt>

# Implementation Notes

- Prefer an incremental parse flow: hash -> parse -> validate -> persist.
- Keep prompt definitions stable so workflow plans can reference prompt paths reliably.
