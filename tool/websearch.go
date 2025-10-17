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
	// IMPORTANT: WebSearch is a server-side tool provided by Anthropic's API.
	// This function should never actually be called in production - it's only here
	// as a fallback to indicate that the tool definition exists but execution
	// must be handled by Anthropic's servers, not the client.
	query, _ := params["query"].(string)
	allowedDomains, _ := params["allowed_domains"].([]interface{})
	blockedDomains, _ := params["blocked_domains"].([]interface{})

	// Build a descriptive message about what would have been searched
	msg := fmt.Sprintf("WebSearch query: %s", query)
	if len(allowedDomains) > 0 {
		msg += fmt.Sprintf("\nAllowed domains: %v", allowedDomains)
	}
	if len(blockedDomains) > 0 {
		msg += fmt.Sprintf("\nBlocked domains: %v", blockedDomains)
	}

	return ToolResult{
		Title:  "WebSearch (Server-side Tool)",
		Output: msg + "\n\nNote: WebSearch is a server-side tool that must be executed by Anthropic's API infrastructure. This client-side handler should not be invoked during normal operation.",
		Error:  fmt.Errorf("websearch is a server-side tool and should be handled by Anthropic's API, not executed client-side"),
	}, nil
}
