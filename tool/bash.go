package tool

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"time"
)

const (
	MaxOutputLength = 30000
	DefaultTimeout  = 2 * time.Minute
	MaxTimeout      = 10 * time.Minute
)

// BashTool creates the bash command execution tool
func BashTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "bash",
		Name: "bash",
		Description: `Execute bash commands in the terminal.

Usage:
- The command argument is required
- You can specify an optional timeout in milliseconds (up to 600000ms / 10 minutes)
- It is very helpful if you write a clear, concise description of what this command does in 5-10 words
- If the output exceeds 30000 characters, output will be truncated before being returned

Important notes:
- Try to maintain your current working directory throughout the session by using absolute paths
- Use '&&' to chain commands that depend on each other
- DO NOT use commands that require interactive input`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"command": map[string]interface{}{
					"type":        "string",
					"description": "The command to execute",
				},
				"description": map[string]interface{}{
					"type":        "string",
					"description": "Clear, concise description of what this command does in 5-10 words",
				},
				"timeout": map[string]interface{}{
					"type":        "number",
					"description": "Optional timeout in milliseconds (max 600000)",
				},
			},
			"required": []string{"command", "description"},
		},
		Execute: executeBash,
	}
}

func executeBash(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	command, ok := params["command"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("command parameter is required")
	}

	description, _ := params["description"].(string)

	// Get timeout
	timeout := DefaultTimeout
	if timeoutParam, ok := params["timeout"].(float64); ok {
		timeout = time.Duration(timeoutParam) * time.Millisecond
		if timeout > MaxTimeout {
			timeout = MaxTimeout
		}
	}

	// Create context with timeout
	execCtx, cancel := context.WithTimeout(ctx.Abort, timeout)
	defer cancel()

	// Execute command
	cmd := exec.CommandContext(execCtx, "bash", "-c", command)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	// Combine stdout and stderr
	output := stdout.String()
	if stderr.Len() > 0 {
		if len(output) > 0 {
			output += "\n"
		}
		output += stderr.String()
	}

	// Truncate if too long
	if len(output) > MaxOutputLength {
		output = output[:MaxOutputLength] + "\n... (output truncated)"
	}

	title := description
	if title == "" {
		title = command
	}

	if err != nil {
		return ToolResult{
			Title:  title,
			Output: fmt.Sprintf("Command failed: %v\n\nOutput:\n%s", err, output),
			Error:  err,
		}, nil
	}

	return ToolResult{
		Title:  title,
		Output: output,
	}, nil
}
