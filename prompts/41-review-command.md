# Review Command

<metadata>
  <priority>medium</priority>
  <category>cli-feature</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/, agent/, server/</affects>
</metadata>

## Objective

Implement a `/review` slash command and `agent review` CLI command for automated code review of staged or recent changes.

<context>
Codex provides `/review` for in-session code review and `codex review` for non-interactive reviews. This is useful for:
- Pre-commit code review
- PR review automation
- Finding bugs and issues in changes
- Code quality feedback

The review command analyzes git diff and provides structured feedback on issues, improvements, and best practices.
</context>

## Requirements

<functional-requirements>
1. `/review` slash command in TUI:
   - Review current staged/unstaged changes
   - Show structured feedback in conversation
2. `agent review` CLI command:
   - Non-interactive mode for CI/CD
   - Output formats: text, json, markdown
   - Exit codes based on findings
3. Review capabilities:
   - Bug detection
   - Security issues
   - Code style/quality
   - Potential improvements
   - Test coverage suggestions
4. Configurable review model
5. Focus on specific files or changes
</functional-requirements>

<technical-requirements>
1. Add `/review` handler to TUI
2. Add `review` subcommand to CLI
3. Create review prompt template
4. Parse and format review output
5. Integrate with git diff
6. Support review_model configuration
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add /review and review subcommand
- `tui/review.go` (CREATE) - Review command implementation
- `agent/review.py` (CREATE) - Review logic and prompts
- `config/defaults.py` - Add review_model setting
</files-to-modify>

<review-prompt>
```python
REVIEW_PROMPT = """You are a code reviewer. Analyze the following code changes and provide a structured review.

## Code Changes (Git Diff)
```diff
{diff}
```

## Review Guidelines
1. **Critical Issues**: Security vulnerabilities, bugs, crashes
2. **Warnings**: Potential issues, edge cases, performance
3. **Suggestions**: Code quality, readability, best practices
4. **Positive Notes**: Good patterns and practices observed

## Output Format
Provide your review in this format:

### Critical Issues
- [File:Line] Description of issue

### Warnings
- [File:Line] Description of warning

### Suggestions
- [File:Line] Suggestion for improvement

### Positive Notes
- Notable good practices or patterns

### Summary
Brief summary of the review (1-2 sentences).

If no changes to review, respond with "No changes to review."
"""
```
</review-prompt>

<slash-command>
```go
// In TUI slash command handler
case "/review":
    args := parseArgs(input)

    // Get diff to review
    var diff string
    if slices.Contains(args, "--staged") {
        diff, _ = runGitCommand("diff", "--staged")
    } else if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
        // Review specific file
        diff, _ = runGitCommand("diff", args[0])
    } else {
        // Review all changes
        diff, _ = runGitCommand("diff")
        if diff == "" {
            diff, _ = runGitCommand("diff", "--staged")
        }
    }

    if diff == "" {
        fmt.Println("No changes to review")
        return nil
    }

    // Send review request to agent
    return m.sendMessage(fmt.Sprintf("/review\n\n```diff\n%s\n```", diff))
```
</slash-command>

<cli-command>
```go
// tui/review.go

var reviewCmd = &cobra.Command{
    Use:   "review",
    Short: "Run code review on changes",
    Long:  "Analyze staged or recent changes and provide code review feedback",
    RunE:  runReview,
}

func init() {
    rootCmd.AddCommand(reviewCmd)

    reviewCmd.Flags().Bool("staged", false, "Review only staged changes")
    reviewCmd.Flags().StringP("output", "o", "text", "Output format: text, json, markdown")
    reviewCmd.Flags().String("model", "", "Model to use for review")
    reviewCmd.Flags().StringSlice("files", nil, "Specific files to review")
}

func runReview(cmd *cobra.Command, args []string) error {
    // Get diff
    staged, _ := cmd.Flags().GetBool("staged")
    files, _ := cmd.Flags().GetStringSlice("files")

    diff, err := getDiff(staged, files)
    if err != nil {
        return fmt.Errorf("failed to get diff: %w", err)
    }

    if diff == "" {
        fmt.Println("No changes to review")
        return nil
    }

    // Get review from agent
    outputFormat, _ := cmd.Flags().GetString("output")
    model, _ := cmd.Flags().GetString("model")

    review, err := client.Review(diff, model)
    if err != nil {
        return fmt.Errorf("review failed: %w", err)
    }

    // Format output
    switch outputFormat {
    case "json":
        return outputJSON(review)
    case "markdown":
        return outputMarkdown(review)
    default:
        return outputText(review)
    }
}

func getDiff(staged bool, files []string) (string, error) {
    args := []string{"diff"}
    if staged {
        args = append(args, "--staged")
    }
    if len(files) > 0 {
        args = append(args, "--")
        args = append(args, files...)
    }

    output, err := exec.Command("git", args...).Output()
    return string(output), err
}
```
</cli-command>

<review-api>
```python
# server/routes/review.py

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

class ReviewRequest(BaseModel):
    diff: str
    model: Optional[str] = None

class ReviewIssue(BaseModel):
    severity: str  # critical, warning, suggestion
    file: str
    line: Optional[int]
    message: str

class ReviewResponse(BaseModel):
    issues: list[ReviewIssue]
    positive_notes: list[str]
    summary: str
    model_used: str

@router.post("/review")
async def run_review(request: ReviewRequest) -> ReviewResponse:
    """Run code review on provided diff."""
    model = request.model or config.get("review_model") or config.get("model")

    # Create review prompt
    prompt = REVIEW_PROMPT.format(diff=request.diff)

    # Run agent for review
    result = await run_agent_single_turn(
        model=model,
        prompt=prompt,
        tools=[],  # No tools needed for review
    )

    # Parse structured output
    issues, positive, summary = parse_review_output(result.content)

    return ReviewResponse(
        issues=issues,
        positive_notes=positive,
        summary=summary,
        model_used=model,
    )
```
</review-api>

<review-output>
```
╭──────────────────── Code Review ─────────────────────╮
│                                                       │
│ ⚠️  CRITICAL ISSUES (1)                              │
│ ────────────────────────────────────────────────────  │
│ • auth.py:45 - SQL injection vulnerability in login  │
│   query. Use parameterized queries instead.          │
│                                                       │
│ ⚡ WARNINGS (2)                                       │
│ ────────────────────────────────────────────────────  │
│ • auth.py:23 - Password not hashed before storage    │
│ • routes.py:67 - Missing rate limiting on login      │
│                                                       │
│ 💡 SUGGESTIONS (3)                                   │
│ ────────────────────────────────────────────────────  │
│ • auth.py:12 - Consider extracting to constant       │
│ • auth.py:34 - Add docstring for clarity             │
│ • routes.py:45 - Could use dependency injection      │
│                                                       │
│ ✓ POSITIVE NOTES                                     │
│ ────────────────────────────────────────────────────  │
│ • Good use of type hints throughout                  │
│ • Clean separation of concerns                       │
│                                                       │
│ SUMMARY: Found 1 critical security issue that should │
│ be addressed before merging. Overall code quality    │
│ is good with proper structure.                       │
│                                                       │
╰───────────────────────────────────────────────────────╯
```
</review-output>

## Acceptance Criteria

<criteria>
- [ ] `/review` command in TUI reviews changes
- [ ] `agent review` CLI command for non-interactive use
- [ ] Reviews staged changes with --staged flag
- [ ] Reviews specific files when specified
- [ ] Output formats: text, json, markdown
- [ ] Structured output with severity levels
- [ ] Summary provided for quick overview
- [ ] Configurable review model
- [ ] Exit code based on critical issues (for CI)
- [ ] "No changes" message when nothing to review
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test /review with various code changes
3. Test CLI review command with output formats
4. Test exit codes for CI usage
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `41-review-command.md` to `41-review-command.complete.md`
</completion>
