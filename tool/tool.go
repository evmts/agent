package tool

import (
	"context"
	"fmt"
)

// ToolDefinition defines the structure of a tool that can be used by Claude
type ToolDefinition struct {
	ID          string
	Name        string
	Description string
	InputSchema map[string]interface{}
	Execute     func(params map[string]interface{}, ctx ToolContext) (ToolResult, error)
}

// ToolContext provides context information for tool execution
type ToolContext struct {
	SessionID string
	MessageID string
	Abort     context.Context
	Mode      string // "normal", "plan", "bypass"
}

// ToolResult represents the result of a tool execution
type ToolResult struct {
	Title    string
	Output   string
	Metadata map[string]interface{}
	Error    error
}

// ToolRegistry manages all available tools
type ToolRegistry struct {
	tools map[string]*ToolDefinition
}

// NewToolRegistry creates a new tool registry with built-in tools
func NewToolRegistry() *ToolRegistry {
	registry := &ToolRegistry{
		tools: make(map[string]*ToolDefinition),
	}

	// Register built-in tools
	registry.Register(BashTool())
	registry.Register(ReadTool())
	registry.Register(EditTool())
	registry.Register(WriteTool())
	registry.Register(GrepTool())
	registry.Register(LspHoverTool())
	registry.Register(LspDiagnosticsTool())
	registry.Register(GlobTool())
	registry.Register(MultiEditTool())
	registry.Register(ListTool())
	registry.Register(TaskTool())
	registry.Register(PatchTool())
	registry.Register(WebFetchTool())
	registry.Register(WebSearchTool())
	registry.Register(TodoWriteTool())
	registry.Register(TodoReadTool())

	return registry
}

// Register adds a tool to the registry
func (r *ToolRegistry) Register(tool *ToolDefinition) {
	r.tools[tool.ID] = tool
}

// Get retrieves a tool by ID
func (r *ToolRegistry) Get(id string) (*ToolDefinition, error) {
	tool, ok := r.tools[id]
	if !ok {
		return nil, fmt.Errorf("tool not found: %s", id)
	}
	return tool, nil
}

// GetAll returns all registered tools
func (r *ToolRegistry) GetAll() []*ToolDefinition {
	tools := make([]*ToolDefinition, 0, len(r.tools))
	for _, tool := range r.tools {
		tools = append(tools, tool)
	}
	return tools
}

// Execute runs a tool with the given parameters
func (r *ToolRegistry) Execute(id string, params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	tool, err := r.Get(id)
	if err != nil {
		return ToolResult{}, err
	}

	// In plan mode, don't actually execute
	if ctx.Mode == "plan" {
		return ToolResult{
			Title:  fmt.Sprintf("[PLAN] %s", tool.Name),
			Output: fmt.Sprintf("Would execute %s with params: %v", tool.Name, params),
		}, nil
	}

	return tool.Execute(params, ctx)
}
