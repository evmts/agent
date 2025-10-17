package main

import (
	"agent/tool"
	"context"
	"encoding/json"
	"fmt"

	"github.com/anthropics/anthropic-sdk-go"
	tea "github.com/charmbracelet/bubbletea"
)

// toolUseMsg represents a tool execution request from Claude
type toolUseMsg struct {
	toolName       string
	toolID         string
	input          map[string]interface{}
	toolUseBlock   anthropic.ContentBlockUnion // Original block from Claude
	precedingText  string                       // Text content that came before the tool use
}

// toolResultMsg represents the result of a tool execution
type toolResultMsg struct {
	toolName string
	toolID   string
	result   tool.ToolResult
}

// Convert our tool definitions to Anthropic API format
func buildAnthropicTools(registry *tool.ToolRegistry) []anthropic.ToolUnionParam {
	tools := registry.GetAll()
	apiTools := make([]anthropic.ToolUnionParam, len(tools))

	for i, t := range tools {
		// Extract schema properties
		schema := t.InputSchema
		properties, _ := schema["properties"]
		required, _ := schema["required"].([]string)

		inputSchema := anthropic.ToolInputSchemaParam{
			Properties: properties,
			Required:   required,
			Type:       "object",
		}

		toolUnion := anthropic.ToolUnionParamOfTool(inputSchema, t.Name)
		if desc := toolUnion.OfTool; desc != nil {
			desc.Description = anthropic.Opt(t.Description)
		}

		apiTools[i] = toolUnion
	}

	return apiTools
}

// sendToClaudeAPI sends a message to Claude and handles tool use
func sendToClaudeAPIWithTools(
	client anthropic.Client,
	selectedModel anthropic.Model,
	history []message,
	userInput string,
	registry *tool.ToolRegistry,
	currentMode mode,
) tea.Msg {
	ctx := context.Background()

	// Build message history for API
	messages := buildMessageHistory(history, userInput)

	// Build tools
	tools := buildAnthropicTools(registry)

	// Send request to Claude
	resp, err := client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     selectedModel,
		MaxTokens: 4096,
		Messages:  messages,
		Tools:     tools,
	})

	if err != nil {
		return errMsg(err)
	}

	// Handle response - could have multiple content blocks
	var textParts []string
	var firstToolUse *toolUseMsg

	for _, content := range resp.Content {
		if content.Type == "text" {
			textParts = append(textParts, content.Text)
		} else if content.Type == "tool_use" && firstToolUse == nil {
			// Parse tool input
			var input map[string]interface{}
			if err := json.Unmarshal([]byte(content.Input), &input); err != nil {
				return errMsg(fmt.Errorf("failed to parse tool input: %v", err))
			}

			// Capture any text that came before the tool use
			precedingText := ""
			if len(textParts) > 0 {
				precedingText = fmt.Sprintf("%v", textParts)
			}

			firstToolUse = &toolUseMsg{
				toolName:      content.Name,
				toolID:        content.ID,
				input:         input,
				toolUseBlock:  content,
				precedingText: precedingText,
			}
		}
	}

	// If there's a tool use, return it (even if there was text before it)
	if firstToolUse != nil {
		return *firstToolUse
	}

	// If there's text content, return it
	if len(textParts) > 0 {
		return responseMsg(fmt.Sprintf("%v", textParts))
	}

	return errMsg(fmt.Errorf("no response from Claude"))
}

// continueWithToolResult sends the tool result back to Claude and gets the final response
func continueWithToolResult(
	client anthropic.Client,
	selectedModel anthropic.Model,
	history []message,
	toolResult toolResultMsg,
	registry *tool.ToolRegistry,
	currentMode mode,
) tea.Msg {
	ctx := context.Background()

	// Build message history including the tool result
	messages := buildMessageHistoryWithToolResult(history)

	// Build tools
	tools := buildAnthropicTools(registry)

	// Send request to Claude with the tool result
	resp, err := client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     selectedModel,
		MaxTokens: 4096,
		Messages:  messages,
		Tools:     tools,
	})

	if err != nil {
		return errMsg(err)
	}

	// Handle response - could have multiple content blocks
	var textParts []string
	var firstToolUse *toolUseMsg

	for _, content := range resp.Content {
		if content.Type == "text" {
			textParts = append(textParts, content.Text)
		} else if content.Type == "tool_use" && firstToolUse == nil {
			// Parse tool input
			var input map[string]interface{}
			if err := json.Unmarshal([]byte(content.Input), &input); err != nil {
				return errMsg(fmt.Errorf("failed to parse tool input: %v", err))
			}

			// Capture any text that came before the tool use
			precedingText := ""
			if len(textParts) > 0 {
				precedingText = fmt.Sprintf("%v", textParts)
			}

			firstToolUse = &toolUseMsg{
				toolName:      content.Name,
				toolID:        content.ID,
				input:         input,
				toolUseBlock:  content,
				precedingText: precedingText,
			}
		}
	}

	// If there's a tool use, return it (even if there was text before it)
	if firstToolUse != nil {
		return *firstToolUse
	}

	// If there's text content, return it
	if len(textParts) > 0 {
		return responseMsg(fmt.Sprintf("%v", textParts))
	}

	return errMsg(fmt.Errorf("no response from Claude"))
}

// buildMessageHistory converts our message history to Anthropic format
func buildMessageHistory(history []message, userInput string) []anthropic.MessageParam {
	var messages []anthropic.MessageParam

	for _, msg := range history {
		if msg.role == "user" {
			messages = append(messages, anthropic.NewUserMessage(
				anthropic.NewTextBlock(msg.content),
			))
		} else if msg.role == "assistant" && !msg.isToolUse && !msg.isToolResult {
			messages = append(messages, anthropic.NewAssistantMessage(
				anthropic.NewTextBlock(msg.content),
			))
		}
	}

	// Add the new user input
	if userInput != "" {
		messages = append(messages, anthropic.NewUserMessage(
			anthropic.NewTextBlock(userInput),
		))
	}

	return messages
}

// buildMessageHistoryWithToolResult builds message history including tool use and results
func buildMessageHistoryWithToolResult(history []message) []anthropic.MessageParam {
	var messages []anthropic.MessageParam

	// Group messages properly for the API
	// The API expects: user -> assistant (with tool_use) -> user (with tool_result) -> assistant...

	for _, msg := range history {
		if msg.role == "user" && !msg.isToolResult {
			// Regular user message
			messages = append(messages, anthropic.NewUserMessage(
				anthropic.NewTextBlock(msg.content),
			))
		} else if msg.isToolUse && msg.toolUseBlock != nil {
			// Assistant message with tool_use block
			messages = append(messages, anthropic.NewAssistantMessage(
				anthropic.NewToolUseBlock(msg.toolUseBlock.ID, msg.toolUseBlock.Input, msg.toolUseBlock.Name),
			))
		} else if msg.isToolResult {
			// Tool result - send as user message with tool_result block
			messages = append(messages, anthropic.NewUserMessage(
				anthropic.NewToolResultBlock(msg.toolUseID, msg.content, msg.Error != nil),
			))
		} else if msg.role == "assistant" && !msg.isToolUse && !msg.isToolResult {
			// Regular assistant text response
			messages = append(messages, anthropic.NewAssistantMessage(
				anthropic.NewTextBlock(msg.content),
			))
		}
	}

	return messages
}
