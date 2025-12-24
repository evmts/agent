---
name: CodeReview
client: anthropic/claude-sonnet

inputs:
  diff: string
  context: string?
  rules: string[]?

output:
  approved: boolean
  comments:
    - file: string
      line: integer
      severity: info | warning | error
      message: string
      suggestion: string?
  summary: string
---

Review this code change for production deployment.

{% if context %}

## Project Guidelines

{{ context }}
{% endif %}

## Code to Review

```diff
{{ diff }}
```

{% if rules %}

## Review Criteria

{% for rule in rules %}
- {{ rule }}
{% endfor %}
{% endif %}

## Instructions

Focus on:
- Logic errors and bugs
- Security vulnerabilities
- Performance issues

{{ output_schema }}
