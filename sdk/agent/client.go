// Package agent provides a Go SDK for the OpenCode-compatible agent server.
//
// This SDK implements the OpenCode API specification from:
// ../opencode/packages/sdk/openapi.json
//
// Example usage:
//
//	client := agent.NewClient("http://localhost:8000")
//
//	// Create a session
//	session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
//	    Title: agent.String("My Session"),
//	})
//
//	// Send a message with streaming
//	eventCh, err := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
//	    Parts: []interface{}{
//	        agent.TextPartInput{Type: "text", Text: "Hello!"},
//	    },
//	})
//	for event := range eventCh {
//	    // Handle streaming events
//	}
package agent

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client is the SDK client for the OpenCode-compatible agent server.
type Client struct {
	baseURL    string
	httpClient *http.Client
	directory  *string // Optional directory query param
}

// ClientOption configures the client.
type ClientOption func(*Client)

// WithHTTPClient sets a custom HTTP client.
func WithHTTPClient(c *http.Client) ClientOption {
	return func(client *Client) {
		client.httpClient = c
	}
}

// WithDirectory sets the directory query parameter for all requests.
func WithDirectory(dir string) ClientOption {
	return func(client *Client) {
		client.directory = &dir
	}
}

// WithTimeout sets the HTTP client timeout.
func WithTimeout(d time.Duration) ClientOption {
	return func(client *Client) {
		client.httpClient.Timeout = d
	}
}

// NewClient creates a new SDK client.
func NewClient(baseURL string, opts ...ClientOption) *Client {
	c := &Client{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}

	for _, opt := range opts {
		opt(c)
	}

	return c
}

// Helper to create string pointers
func String(s string) *string {
	return &s
}

// Helper to create bool pointers
func Bool(b bool) *bool {
	return &b
}

// addDirectoryParam adds the directory query parameter if set.
func (c *Client) addDirectoryParam(u *url.URL) {
	if c.directory != nil {
		q := u.Query()
		q.Set("directory", *c.directory)
		u.RawQuery = q.Encode()
	}
}

// buildURL builds a URL with the directory parameter.
func (c *Client) buildURL(path string, queryParams ...map[string]string) string {
	u, _ := url.Parse(c.baseURL + path)
	c.addDirectoryParam(u)

	if len(queryParams) > 0 {
		q := u.Query()
		for _, params := range queryParams {
			for k, v := range params {
				q.Set(k, v)
			}
		}
		u.RawQuery = q.Encode()
	}

	return u.String()
}

// doRequest performs an HTTP request and decodes the JSON response.
func (c *Client) doRequest(ctx context.Context, method, path string, body interface{}, result interface{}) error {
	var bodyReader io.Reader
	if body != nil {
		jsonBody, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request body: %w", err)
		}
		bodyReader = bytes.NewReader(jsonBody)
	}

	reqURL := c.buildURL(path)
	req, err := http.NewRequestWithContext(ctx, method, reqURL, bodyReader)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(bodyBytes))
	}

	if result != nil {
		if err := json.NewDecoder(resp.Body).Decode(result); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}

	return nil
}

// doSSERequest performs an SSE streaming request.
func (c *Client) doSSERequest(ctx context.Context, method, path string, body interface{}) (<-chan *Event, <-chan error, error) {
	var bodyReader io.Reader
	if body != nil {
		jsonBody, err := json.Marshal(body)
		if err != nil {
			return nil, nil, fmt.Errorf("marshal request body: %w", err)
		}
		bodyReader = bytes.NewReader(jsonBody)
	}

	reqURL := c.buildURL(path)
	req, err := http.NewRequestWithContext(ctx, method, reqURL, bodyReader)
	if err != nil {
		return nil, nil, fmt.Errorf("create request: %w", err)
	}

	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Connection", "keep-alive")

	// Use a client without timeout for SSE
	sseClient := &http.Client{}
	resp, err := sseClient.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("do request: %w", err)
	}

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(bodyBytes))
	}

	eventCh := make(chan *Event, 100)
	errCh := make(chan error, 1)

	go func() {
		defer close(eventCh)
		defer close(errCh)
		defer resp.Body.Close()

		reader := bufio.NewReader(resp.Body)
		var eventType string
		var dataLines []string

		for {
			select {
			case <-ctx.Done():
				errCh <- ctx.Err()
				return
			default:
			}

			line, err := reader.ReadString('\n')
			if err != nil {
				if err != io.EOF {
					errCh <- err
				}
				return
			}

			line = strings.TrimSpace(line)

			if line == "" {
				// Empty line = end of event
				if eventType != "" || len(dataLines) > 0 {
					data := strings.Join(dataLines, "\n")
					if data != "" {
						var event Event
						if err := json.Unmarshal([]byte(data), &event); err != nil {
							// Try parsing as just the event type
							event = Event{Type: eventType, Properties: json.RawMessage(data)}
						}
						if event.Type == "" {
							event.Type = eventType
						}
						eventCh <- &event
					}
					eventType = ""
					dataLines = nil
				}
				continue
			}

			if strings.HasPrefix(line, "event:") {
				eventType = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
			} else if strings.HasPrefix(line, "data:") {
				data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
				dataLines = append(dataLines, data)
			}
		}
	}()

	return eventCh, errCh, nil
}

// =============================================================================
// Health
// =============================================================================

// Health checks the server health.
func (c *Client) Health(ctx context.Context) (*HealthResponse, error) {
	var result HealthResponse
	if err := c.doRequest(ctx, http.MethodGet, "/health", nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// =============================================================================
// Sessions
// =============================================================================

// ListSessions returns all sessions.
func (c *Client) ListSessions(ctx context.Context) ([]Session, error) {
	var result []Session
	if err := c.doRequest(ctx, http.MethodGet, "/session", nil, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// CreateSession creates a new session.
func (c *Client) CreateSession(ctx context.Context, req *CreateSessionRequest) (*Session, error) {
	if req == nil {
		req = &CreateSessionRequest{}
	}
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// GetSession retrieves a session by ID.
func (c *Client) GetSession(ctx context.Context, sessionID string) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodGet, "/session/"+sessionID, nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// DeleteSession deletes a session.
func (c *Client) DeleteSession(ctx context.Context, sessionID string) error {
	var result bool
	return c.doRequest(ctx, http.MethodDelete, "/session/"+sessionID, nil, &result)
}

// UpdateSession updates a session's title or archived status.
func (c *Client) UpdateSession(ctx context.Context, sessionID string, req *UpdateSessionRequest) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPatch, "/session/"+sessionID, req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// =============================================================================
// Messages
// =============================================================================

// ListMessages returns messages in a session.
func (c *Client) ListMessages(ctx context.Context, sessionID string, limit *int) ([]MessageWithParts, error) {
	path := "/session/" + sessionID + "/message"
	if limit != nil {
		path = fmt.Sprintf("%s?limit=%d", path, *limit)
	}

	var result []MessageWithParts
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// GetMessage retrieves a specific message.
func (c *Client) GetMessage(ctx context.Context, sessionID, messageID string) (*MessageWithParts, error) {
	var result MessageWithParts
	path := fmt.Sprintf("/session/%s/message/%s", sessionID, messageID)
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// StreamEvent represents an event from SendMessage streaming.
type StreamEvent struct {
	Type    string // "message.updated", "part.updated", etc.
	Message *Message
	Part    *Part
	Raw     json.RawMessage
}

// SendMessage sends a prompt and streams the response.
// Returns a channel of events. Close the context to stop streaming.
func (c *Client) SendMessage(ctx context.Context, sessionID string, req *PromptRequest) (<-chan *StreamEvent, <-chan error, error) {
	path := "/session/" + sessionID + "/message"

	eventCh, errCh, err := c.doSSERequest(ctx, http.MethodPost, path, req)
	if err != nil {
		return nil, nil, err
	}

	streamCh := make(chan *StreamEvent, 100)
	streamErrCh := make(chan error, 1)

	go func() {
		defer close(streamCh)
		defer close(streamErrCh)

		for {
			select {
			case <-ctx.Done():
				streamErrCh <- ctx.Err()
				return
			case err, ok := <-errCh:
				if ok && err != nil {
					streamErrCh <- err
				}
				return
			case event, ok := <-eventCh:
				if !ok {
					return
				}

				streamEvent := &StreamEvent{
					Type: event.Type,
					Raw:  event.Properties,
				}

				// Parse the event based on type
				switch event.Type {
				case "message.updated":
					var msgEvent MessageEvent
					if err := json.Unmarshal(event.Properties, &msgEvent); err == nil {
						streamEvent.Message = &msgEvent.Info
					}
				case "part.updated":
					var part Part
					if err := json.Unmarshal(event.Properties, &part); err == nil {
						streamEvent.Part = &part
					}
				}

				streamCh <- streamEvent
			}
		}
	}()

	return streamCh, streamErrCh, nil
}

// SendMessageSync sends a prompt and waits for the complete response.
func (c *Client) SendMessageSync(ctx context.Context, sessionID string, req *PromptRequest) (*MessageWithParts, error) {
	eventCh, errCh, err := c.SendMessage(ctx, sessionID, req)
	if err != nil {
		return nil, err
	}

	var result MessageWithParts
	var parts []Part

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case err := <-errCh:
			if err != nil {
				return nil, err
			}
			result.Parts = parts
			return &result, nil
		case event, ok := <-eventCh:
			if !ok {
				result.Parts = parts
				return &result, nil
			}

			if event.Message != nil && event.Message.IsAssistant() {
				result.Info = *event.Message
			}
			if event.Part != nil {
				// Update or add part
				found := false
				for i, p := range parts {
					if p.ID == event.Part.ID {
						parts[i] = *event.Part
						found = true
						break
					}
				}
				if !found {
					parts = append(parts, *event.Part)
				}
			}
		}
	}
}

// =============================================================================
// Session Actions
// =============================================================================

// AbortSession aborts an active session.
func (c *Client) AbortSession(ctx context.Context, sessionID string) error {
	var result bool
	return c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/abort", nil, &result)
}

// GetSessionDiff returns file diffs for a session.
func (c *Client) GetSessionDiff(ctx context.Context, sessionID string, messageID *string) ([]FileDiff, error) {
	path := "/session/" + sessionID + "/diff"
	if messageID != nil {
		path = fmt.Sprintf("%s?messageID=%s", path, *messageID)
	}

	var result []FileDiff
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// ForkSession creates a fork of a session.
func (c *Client) ForkSession(ctx context.Context, sessionID string, req *ForkRequest) (*Session, error) {
	if req == nil {
		req = &ForkRequest{}
	}
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/fork", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// RevertSession reverts a session to a specific message.
func (c *Client) RevertSession(ctx context.Context, sessionID string, req *RevertRequest) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/revert", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// UnrevertSession undoes a revert on a session.
func (c *Client) UnrevertSession(ctx context.Context, sessionID string) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/unrevert", nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// =============================================================================
// Global Events
// =============================================================================

// GlobalEvent represents an event from the global event stream.
type GlobalEvent struct {
	Type    string
	Session *Session
	Message *Message
	Part    *Part
	Raw     json.RawMessage
}

// SubscribeToEvents subscribes to the global event stream.
// Returns a channel of events. Close the context to stop subscribing.
func (c *Client) SubscribeToEvents(ctx context.Context) (<-chan *GlobalEvent, <-chan error, error) {
	eventCh, errCh, err := c.doSSERequest(ctx, http.MethodGet, "/global/event", nil)
	if err != nil {
		return nil, nil, err
	}

	globalCh := make(chan *GlobalEvent, 100)
	globalErrCh := make(chan error, 1)

	go func() {
		defer close(globalCh)
		defer close(globalErrCh)

		for {
			select {
			case <-ctx.Done():
				globalErrCh <- ctx.Err()
				return
			case err, ok := <-errCh:
				if ok && err != nil {
					globalErrCh <- err
				}
				return
			case event, ok := <-eventCh:
				if !ok {
					return
				}

				globalEvent := &GlobalEvent{
					Type: event.Type,
					Raw:  event.Properties,
				}

				// Parse based on event type
				switch {
				case strings.HasPrefix(event.Type, "session."):
					var sessEvent SessionEvent
					if err := json.Unmarshal(event.Properties, &sessEvent); err == nil {
						globalEvent.Session = &sessEvent.Info
					}
				case strings.HasPrefix(event.Type, "message."):
					var msgEvent MessageEvent
					if err := json.Unmarshal(event.Properties, &msgEvent); err == nil {
						globalEvent.Message = &msgEvent.Info
					}
				case event.Type == "part.updated":
					var part Part
					if err := json.Unmarshal(event.Properties, &part); err == nil {
						globalEvent.Part = &part
					}
				}

				globalCh <- globalEvent
			}
		}
	}()

	return globalCh, globalErrCh, nil
}

// GetMCPServers retrieves the list of MCP servers and their status.
func (c *Client) GetMCPServers(ctx context.Context) (*MCPServersResponse, error) {
	u, err := url.Parse(c.baseURL + "/mcp/servers")
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	c.addDirectoryParam(u)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(body))
	}

	var result MCPServersResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	return &result, nil
}
