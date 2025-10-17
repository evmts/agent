package tool

import (
	"fmt"
	"strings"
)

// Agent represents a specialized agent type
type Agent struct {
	Name        string
	Description string
	Mode        string
	Tools       map[string]bool
	BuiltIn     bool
	TopP        *float64
	Temperature *float64
	Model       *ModelConfig
	Prompt      string
	Options     map[string]interface{}
	Permission  PermissionConfig
}

// ModelConfig represents model configuration
type ModelConfig struct {
	ModelID    string
	ProviderID string
}

// PermissionConfig represents permission settings
type PermissionConfig struct {
	Edit     string
	Bash     map[string]string
	WebFetch string
}

// DefaultAgents returns the list of available agent types
func DefaultAgents() []Agent {
	return []Agent{
		{
			Name:        "general",
			Description: "General-purpose agent for researching complex questions, searching for code, and executing multi-step tasks. When you are searching for a keyword or file and are not confident that you will find the right match in the first few tries use this agent to perform the search for you.",
			Mode:        "subagent",
			BuiltIn:     true,
			Tools: map[string]bool{
				"todoread":  false,
				"todowrite": false,
				"task":      false, // Agents can't spawn other task agents
			},
			Permission: PermissionConfig{
				Edit:     "allow",
				Bash:     map[string]string{"*": "allow"},
				WebFetch: "allow",
			},
			Options: map[string]interface{}{},
		},
		{
			Name:    "build",
			Mode:    "primary",
			BuiltIn: true,
			Tools: map[string]bool{
				"task": false,
			},
			Permission: PermissionConfig{
				Edit:     "allow",
				Bash:     map[string]string{"*": "allow"},
				WebFetch: "allow",
			},
			Options: map[string]interface{}{},
		},
		{
			Name:    "plan",
			Mode:    "primary",
			BuiltIn: true,
			Tools: map[string]bool{
				"task": false,
			},
			Permission: PermissionConfig{
				Edit:     "deny",
				Bash:     map[string]string{"*": "ask"},
				WebFetch: "allow",
			},
			Options: map[string]interface{}{},
		},
	}
}

// TaskTool creates the task tool for launching specialized agents
func TaskTool() *ToolDefinition {
	allAgents := DefaultAgents()
	// Filter to only include subagent and all mode agents (exclude primary)
	agents := make([]Agent, 0)
	for _, agent := range allAgents {
		if agent.Mode != "primary" {
			agents = append(agents, agent)
		}
	}

	agentDescriptions := make([]string, len(agents))
	for i, agent := range agents {
		desc := agent.Description
		if desc == "" {
			desc = "This subagent should only be called manually by the user."
		}
		agentDescriptions[i] = fmt.Sprintf("- %s: %s", agent.Name, desc)
	}

	description := strings.ReplaceAll(taskDescription, "{agents}", strings.Join(agentDescriptions, "\n"))

	return &ToolDefinition{
		ID:          "task",
		Name:        "task",
		Description: description,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"description": map[string]interface{}{
					"type":        "string",
					"description": "A short (3-5 words) description of the task",
				},
				"prompt": map[string]interface{}{
					"type":        "string",
					"description": "The task for the agent to perform",
				},
				"subagent_type": map[string]interface{}{
					"type":        "string",
					"description": "The type of specialized agent to use for this task",
				},
			},
			"required": []string{"description", "prompt", "subagent_type"},
		},
		Execute: executeTask,
	}
}

func executeTask(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	description, ok := params["description"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("description parameter is required")
	}

	prompt, ok := params["prompt"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("prompt parameter is required")
	}

	subagentType, ok := params["subagent_type"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("subagent_type parameter is required")
	}

	// Find the agent
	agents := DefaultAgents()
	var selectedAgent *Agent
	for _, agent := range agents {
		if agent.Name == subagentType {
			selectedAgent = &agent
			break
		}
	}

	if selectedAgent == nil {
		return ToolResult{}, fmt.Errorf("unknown agent type: %s is not a valid agent type", subagentType)
	}

	// Note: In TypeScript, plan mode is handled differently through the session system.
	// For now, we'll handle it similarly but this may need adjustment based on
	// how the Go session system implements plan mode.

	// For now, we return a placeholder indicating that the task system is not fully implemented
	// In a full implementation, this would:
	// 1. Create a new session with parentID set to ctx.SessionID
	// 2. Execute the prompt in that session with the agent's tool permissions
	// 3. Capture all tool execution events
	// 4. Return the final result with a summary of tool calls

	// sessionID would be: fmt.Sprintf("%s-subtask-%s", ctx.SessionID, selectedAgent.Name)

	return ToolResult{
		Title: description + fmt.Sprintf(" (@%s subagent)", selectedAgent.Name),
		Output: fmt.Sprintf("Task agent system not fully implemented yet.\n\nWould execute task:\n  Agent: %s\n  Description: %s\n  Prompt: %s\n\nThis requires implementing:\n  - Session creation with parent ID\n  - Agent-specific tool permissions\n  - Tool execution event capture\n  - Result aggregation",
			selectedAgent.Name, description, prompt),
		Metadata: map[string]interface{}{
			"summary": []interface{}{},
		},
	}, nil
}

// taskDescription is the tool description template
const taskDescription = `Launch a new agent to handle complex, multi-step tasks autonomously.

Available agent types and the tools they have access to:
{agents}

When using the Task tool, you must specify a subagent_type parameter to select which agent type to use.

When to use the Task tool:
- When you are instructed to execute custom slash commands. Use the Task tool with the slash command invocation as the entire prompt. The slash command can take arguments. For example: Task(description="Check the file", prompt="/check-file path/to/file.py")

When NOT to use the Task tool:
- If you want to read a specific file path, use the Read or Glob tool instead of the Task tool, to find the match more quickly
- If you are searching for a specific class definition like "class Foo", use the Glob tool instead, to find the match more quickly
- If you are searching for code within a specific file or set of 2-3 files, use the Read tool instead of the Task tool, to find the match more quickly
- Other tasks that are not related to the agent descriptions above


Usage notes:
1. Launch multiple agents concurrently whenever possible, to maximize performance; to do that, use a single message with multiple tool uses
2. When the agent is done, it will return a single message back to you. The result returned by the agent is not visible to the user. To show the user the result, you should send a text message back to the user with a concise summary of the result.
3. Each agent invocation is stateless. You will not be able to send additional messages to the agent, nor will the agent be able to communicate with you outside of its final report. Therefore, your prompt should contain a highly detailed task description for the agent to perform autonomously and you should specify exactly what information the agent should return back to you in its final and only message to you.
4. The agent's outputs should generally be trusted
5. Clearly tell the agent whether you expect it to write code or just to do research (search, file reads, web fetches, etc.), since it is not aware of the user's intent
6. If the agent description mentions that it should be used proactively, then you should try your best to use it without the user having to ask for it first. Use your judgement.

Example usage (NOTE: The agents below are fictional examples for illustration only - use the actual agents listed above):

<example_agent_descriptions>
"code-reviewer": use this agent after you are done writing a signficant piece of code
"greeting-responder": use this agent when to respond to user greetings with a friendly joke
</example_agent_description>

<example>
user: "Please write a function that checks if a number is prime"
assistant: Sure let me write a function that checks if a number is prime
assistant: First let me use the Write tool to write a function that checks if a number is prime
assistant: I'm going to use the Write tool to write the following code:
<code>
function isPrime(n) {
  if (n <= 1) return false
  for (let i = 2; i * i <= n; i++) {
    if (n % i === 0) return false
  }
  return true
}
</code>
<commentary>
Since a signficant piece of code was written and the task was completed, now use the code-reviewer agent to review the code
</commentary>
assistant: Now let me use the code-reviewer agent to review the code
assistant: Uses the Task tool to launch the code-reviewer agent
</example>

<example>
user: "Hello"
<commentary>
Since the user is greeting, use the greeting-responder agent to respond with a friendly joke
</commentary>
assistant: "I'm going to use the Task tool to launch the with the greeting-responder agent"
</example>
`
