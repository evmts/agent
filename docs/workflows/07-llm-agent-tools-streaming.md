<prompt>
  <title>LLM + Agent Steps + Tool System</title>
  <objective>Execute LLM and agent steps, including tool calls, output parsing, and streaming events.</objective>
  <context>
    <file>docs/workflows-engineering.md</file>
    <file>docs/workflows-prd.md</file>
  </context>
  <requirements>
    <item>Render prompts with the Jinja2 parser and validate inputs before execution.</item>
    <item>Execute LLM steps with streaming token output and schema-validated results.</item>
    <item>Implement agent loop with tool invocation and max_turns handling.</item>
    <item>Load built-in tools (read_file, write_file, shell, glob, grep, websearch) and custom tools from paths.</item>
    <item>Emit tool_start/tool_end and llm_token events; persist logs and LLM usage.</item>
  </requirements>
  <deliverables>
    <item>LLM executor module (Claude Code SDK integration) with streaming callbacks.</item>
    <item>Agent executor with tool registry and safe tool execution.</item>
    <item>Tool loader that resolves builtin + custom tools based on prompt specs.</item>
  </deliverables>
  <acceptance>
    <item>LLM step renders prompt, streams tokens, and outputs validated JSON.</item>
    <item>Agent step can call built-in tools and returns structured output.</item>
    <item>Tool calls appear in workflow_logs and SSE stream.</item>
  </acceptance>
  <out_of_scope>
    <item>Workflow discovery or plan generation.</item>
    <item>UI components.</item>
  </out_of_scope>
  <notes>
    <item>Follow the SSE event shapes from the engineering spec.</item>
    <item>Respect tool scoping to repo refs when provided.</item>
  </notes>
</prompt>

# Implementation Notes

- Track token usage and latency in `llm_usage` per step.
- Use schema validation on the final LLM output to enforce contract quality.
