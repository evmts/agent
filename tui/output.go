package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/williamcory/agent/sdk/agent"
)

// ExecOutput represents the JSON output format for exec command.
type ExecOutput struct {
	Success    bool              `json:"success"`
	Messages   []ExecMessage     `json:"messages,omitempty"`
	FinalText  string            `json:"final_text"`
	ToolCalls  []ExecToolCall    `json:"tool_calls,omitempty"`
	Duration   float64           `json:"duration_seconds"`
	TokensUsed int               `json:"tokens_used,omitempty"`
	Error      string            `json:"error,omitempty"`
}

// ExecMessage represents a message in the exec output.
type ExecMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ExecToolCall represents a tool call in the exec output.
type ExecToolCall struct {
	Name   string                 `json:"name"`
	Input  map[string]interface{} `json:"input,omitempty"`
	Output string                 `json:"output,omitempty"`
}

// StreamEvent represents a streaming event output.
type StreamEvent struct {
	Type    string                 `json:"type"`
	Content string                 `json:"content,omitempty"`
	Name    string                 `json:"name,omitempty"`
	Args    map[string]interface{} `json:"args,omitempty"`
}

// OutputFormatter handles different output formats for the exec command.
type OutputFormatter struct {
	format      string // "text", "json", "stream"
	full        bool   // include all messages
	quiet       bool   // suppress status messages
	startTime   time.Time
	messages    []ExecMessage
	toolCalls   []ExecToolCall
	finalText   string
	tokensUsed  int
	hasError    bool
	errorMsg    string
}

// NewOutputFormatter creates a new output formatter.
func NewOutputFormatter(format string, full, quiet bool) *OutputFormatter {
	return &OutputFormatter{
		format:     format,
		full:       full,
		quiet:      quiet,
		startTime:  time.Now(),
		messages:   []ExecMessage{},
		toolCalls:  []ExecToolCall{},
	}
}

// AddUserMessage adds a user message to the output.
func (f *OutputFormatter) AddUserMessage(content string) {
	if f.full {
		f.messages = append(f.messages, ExecMessage{
			Role:    "user",
			Content: content,
		})
	}
}

// AddAssistantMessage adds an assistant message to the output.
func (f *OutputFormatter) AddAssistantMessage(content string) {
	if f.full {
		f.messages = append(f.messages, ExecMessage{
			Role:    "assistant",
			Content: content,
		})
	}
	f.finalText = content
}

// AddToolCall adds a tool call to the output.
func (f *OutputFormatter) AddToolCall(name string, input map[string]interface{}, output string) {
	if f.full {
		f.toolCalls = append(f.toolCalls, ExecToolCall{
			Name:   name,
			Input:  input,
			Output: output,
		})
	}
}

// SetTokensUsed sets the token usage count.
func (f *OutputFormatter) SetTokensUsed(tokens int) {
	f.tokensUsed = tokens
}

// SetError sets an error message.
func (f *OutputFormatter) SetError(err error) {
	f.hasError = true
	f.errorMsg = err.Error()
}

// StreamText outputs streaming text in real-time.
func (f *OutputFormatter) StreamText(text string) {
	if f.format == "stream" {
		event := StreamEvent{
			Type:    "text",
			Content: text,
		}
		data, _ := json.Marshal(event)
		fmt.Println(string(data))
	}
}

// StreamToolCall outputs a streaming tool call event.
func (f *OutputFormatter) StreamToolCall(name string, args map[string]interface{}) {
	if f.format == "stream" {
		event := StreamEvent{
			Type: "tool_call",
			Name: name,
			Args: args,
		}
		data, _ := json.Marshal(event)
		fmt.Println(string(data))
	}
}

// StreamToolResult outputs a streaming tool result event.
func (f *OutputFormatter) StreamToolResult(content string) {
	if f.format == "stream" {
		event := StreamEvent{
			Type:    "tool_result",
			Content: content,
		}
		data, _ := json.Marshal(event)
		fmt.Println(string(data))
	}
}

// StreamDone outputs the final done event for streaming.
func (f *OutputFormatter) StreamDone(success bool) {
	if f.format == "stream" {
		event := map[string]interface{}{
			"type":    "done",
			"success": success,
		}
		data, _ := json.Marshal(event)
		fmt.Println(string(data))
	}
}

// StatusMessage outputs a status message (only if not quiet).
func (f *OutputFormatter) StatusMessage(msg string) {
	if !f.quiet && f.format != "json" && f.format != "stream" {
		fmt.Fprintf(stderr, "%s\n", msg)
	}
}

// Finalize outputs the final result based on the format.
func (f *OutputFormatter) Finalize() {
	duration := time.Since(f.startTime).Seconds()

	switch f.format {
	case "json":
		output := ExecOutput{
			Success:    !f.hasError,
			FinalText:  f.finalText,
			Duration:   duration,
			TokensUsed: f.tokensUsed,
		}
		if f.full {
			output.Messages = f.messages
			output.ToolCalls = f.toolCalls
		}
		if f.hasError {
			output.Error = f.errorMsg
		}
		data, err := json.MarshalIndent(output, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "Error marshaling JSON: %v\n", err)
			return
		}
		fmt.Println(string(data))

	case "stream":
		f.StreamDone(!f.hasError)

	default: // "text"
		if f.hasError {
			// Error already printed to stderr
			return
		}
		// Output only the final assistant message
		fmt.Println(f.finalText)
	}
}

// ExtractTextFromParts extracts text content from message parts.
func ExtractTextFromParts(parts []agent.Part) string {
	var texts []string
	for _, part := range parts {
		if part.IsText() && part.Text != "" {
			texts = append(texts, part.Text)
		}
	}
	return strings.Join(texts, "\n")
}

// GetTokensFromMessage extracts token usage from a message.
func GetTokensFromMessage(msg *agent.Message) int {
	if msg.Tokens != nil {
		return msg.Tokens.Input + msg.Tokens.Output + msg.Tokens.Reasoning
	}
	return 0
}
