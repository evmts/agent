<prompt>
  <title>Jinja2 Prompt Parser + Schema Extraction</title>
  <objective>Parse .prompt.md files, extract frontmatter schemas, and compile/render Jinja2-compatible templates.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Split YAML frontmatter and Markdown body with strict parsing and helpful errors.</item>
    <item>Support Jinja2 features: variables, conditionals, loops, include, extends, block, macro.</item>
    <item>Parse input/output schemas from frontmatter into structured types; produce JSON Schema output.</item>
    <item>Inject output_schema into the render context automatically.</item>
    <item>Cache templates by path + mtime; recompile on change.</item>
  </requirements>
  <deliverables>
    <item>Prompt parser module invoked by Zig via FFI (Rust/C) that returns PromptDefinition objects.</item>
    <item>Validation errors include file path, line number, and a short hint.</item>
    <item>Unit tests or fixture-driven tests for frontmatter parsing and template rendering.</item>
  </deliverables>
  <acceptance>
    <item>Given a valid prompt, parser returns name, client, type, schemas, tools, max_turns, and compiled template.</item>
    <item>Invalid frontmatter (missing name, malformed schema) produces a structured error.</item>
    <item>Template inheritance resolves base prompts from relative paths.</item>
  </acceptance>
  <out_of_scope>
    <item>Executing prompts against LLMs.</item>
    <item>Workflow plan evaluation.</item>
  </out_of_scope>
  <notes>
    <item>Prefer a Jinja2-compatible engine like minijinja for parity.</item>
    <item>Respect default prompt type = llm, and default max_turns for agents.</item>
  </notes>
</prompt>

# Implementation Notes

- Ensure the body template can be rendered with a dict of inputs and injected `output_schema`.
- Support type syntax from the PRD (string?, string[], enums via `a | b | c`).
- Keep prompt definitions stable for hashing and caching in the storage layer.
