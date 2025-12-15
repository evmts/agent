package client

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"claude-tui/internal/messages"
)

// Client handles communication with the AI backend
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a new SSE client
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL:    baseURL,
		httpClient: &http.Client{},
	}
}

// StreamChat sends a message and streams the response via SSE
// It returns a tea.Cmd that handles the streaming
func (c *Client) StreamChat(ctx context.Context, message string, conversationID *string, p *tea.Program) tea.Cmd {
	return func() tea.Msg {
		// Build request body
		reqBody := ChatRequest{
			Message:        message,
			ConversationID: conversationID,
		}
		body, err := json.Marshal(reqBody)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("failed to marshal request: %v", err)}
		}

		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/chat", bytes.NewReader(body))
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("failed to create request: %v", err)}
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "text/event-stream")
		req.Header.Set("Cache-Control", "no-cache")

		// Send request
		resp, err := c.httpClient.Do(req)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("request failed: %v", err)}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return messages.ErrorMsg{Message: fmt.Sprintf("server returned status %d", resp.StatusCode)}
		}

		// Signal stream start
		p.Send(messages.StreamStartMsg{})

		// Parse SSE stream
		scanner := bufio.NewScanner(resp.Body)
		var currentEvent string
		var dataBuffer strings.Builder

		for scanner.Scan() {
			line := scanner.Text()

			// Check for context cancellation
			select {
			case <-ctx.Done():
				return messages.StreamEndMsg{}
			default:
			}

			if strings.HasPrefix(line, "event:") {
				currentEvent = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
			} else if strings.HasPrefix(line, "data:") {
				dataBuffer.WriteString(strings.TrimPrefix(line, "data:"))
			} else if line == "" && currentEvent != "" && dataBuffer.Len() > 0 {
				// Empty line signals end of event
				msg := c.parseEvent(currentEvent, dataBuffer.String())
				if msg != nil {
					p.Send(msg)
				}
				currentEvent = ""
				dataBuffer.Reset()
			}
		}

		if err := scanner.Err(); err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("stream error: %v", err)}
		}

		return messages.StreamEndMsg{}
	}
}

// parseEvent converts an SSE event into a Bubbletea message
func (c *Client) parseEvent(eventType, data string) tea.Msg {
	data = strings.TrimSpace(data)

	switch eventType {
	case "token":
		var evt TokenEvent
		if err := json.Unmarshal([]byte(data), &evt); err != nil {
			return nil
		}
		return messages.TokenMsg{Content: evt.Content}

	case "tool_use":
		var evt ToolUseEvent
		if err := json.Unmarshal([]byte(data), &evt); err != nil {
			return nil
		}
		return messages.ToolUseMsg{Tool: evt.Tool, Input: evt.Input}

	case "tool_result":
		var evt ToolResultEvent
		if err := json.Unmarshal([]byte(data), &evt); err != nil {
			return nil
		}
		return messages.ToolResultMsg{Tool: evt.Tool, Output: evt.Output}

	case "done":
		var evt DoneEvent
		if err := json.Unmarshal([]byte(data), &evt); err != nil {
			return nil
		}
		return messages.DoneMsg{ConversationID: evt.ConversationID}

	case "error":
		var evt ErrorEvent
		if err := json.Unmarshal([]byte(data), &evt); err != nil {
			return messages.ErrorMsg{Message: data}
		}
		return messages.ErrorMsg{Message: evt.Message}
	}

	return nil
}

// HealthCheck checks if the backend is available
func (c *Client) HealthCheck(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/health", nil)
	if err != nil {
		return err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health check failed with status %d", resp.StatusCode)
	}

	return nil
}
