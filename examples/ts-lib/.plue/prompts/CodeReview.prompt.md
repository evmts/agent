---
name: CodeReview
client: anthropic/claude-sonnet

inputs:
  diff: string
  language: string
  guidelines: string?

output:
  approved: boolean
  has_issues: boolean
  summary: string
  issues:
    - file: string
      line: integer
      severity: enum(error, warning, suggestion)
      message: string
---

You are reviewing a {{ language }} code change. Analyze the diff carefully.

{% if guidelines %}
## Project Guidelines

{{ guidelines }}

{% endif %}
## Diff to Review

```diff
{{ diff }}
```

## Review Instructions

Focus on:
1. **Bugs**: Logic errors, null/undefined handling, off-by-one errors
2. **Types**: Missing or incorrect type annotations
3. **Security**: Input validation, injection risks
4. **Performance**: Unnecessary loops, memory leaks
5. **Style**: Naming conventions, code organization

Be constructive. Only flag genuine issues, not stylistic preferences.

{{ output_schema }}
