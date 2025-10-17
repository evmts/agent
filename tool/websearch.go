package tool

import (
	"fmt"
)

// WebSearchTool creates the web search tool definition
// Note: This is a server-side tool provided by Anthropic's API.
// The execution happens on Anthropic's servers, not client-side.
func WebSearchTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "websearch",
		Name: "websearch",
		Description: `
- Allows Claude to search the web and use the results to inform responses
- Provides up-to-date information for current events and recent data
- Returns search result information formatted as search result blocks
- Use this tool for accessing information beyond Claude's knowledge cutoff
- Searches are performed automatically within a single API call

Usage notes:
  - Domain filtering is supported to include or block specific websites
  - Web search is only available in the US
  - Account for "Today's date" in <env>. For example, if <env> says "Today's date: 2025-07-01", and the user wants the latest docs, do not use 2024 in the search query. Use 2025.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"query": map[string]interface{}{
					"type":        "string",
					"description": "The search query to use",
					"minLength":   2,
				},
				"allowed_domains": map[string]interface{}{
					"type":        "array",
					"description": "Only include search results from these domains",
					"items": map[string]interface{}{
						"type": "string",
					},
				},
				"blocked_domains": map[string]interface{}{
					"type":        "array",
					"description": "Never include search results from these domains",
					"items": map[string]interface{}{
						"type": "string",
					},
				},
			},
			"required": []string{"query"},
		},
		Execute: executeWebSearch,
	}
}

func executeWebSearch(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	// This tool is executed server-side by Anthropic's API
	// If this function is called, it means the tool wasn't handled by the server
	query, _ := params["query"].(string)

	return ToolResult{
		Title:  "WebSearch (Server-side)",
		Output: fmt.Sprintf("WebSearch is a server-side tool handled by Anthropic's API. Query: %s", query),
		Error:  fmt.Errorf("websearch should be handled server-side by Anthropic's API"),
	}, nil
}
