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
		if client.httpClient == nil {
			client.httpClient = &http.Client{}
		}
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

// String creates a string pointer (helper for optional fields).
func String(s string) *string {
	return &s
}

// Bool creates a bool pointer (helper for optional fields).
func Bool(b bool) *bool {
	return &b
}

// Int creates an int pointer (helper for optional fields).
func Int(i int) *int {
	return &i
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
			// Check context cancellation before reading
			select {
			case <-ctx.Done():
				return
			default:
			}

			line, err := reader.ReadString('\n')
			if err != nil {
				select {
				case <-ctx.Done():
					return
				default:
					if err != io.EOF {
						errCh <- err
					}
					return
				}
			}

			line = strings.TrimSpace(line)

			if line == "" {
				// Empty line = end of event
				if eventType != "" || len(dataLines) > 0 {
					data := strings.Join(dataLines, "\n")
					if data != "" {
						var event Event
						if err := json.Unmarshal([]byte(data), &event); err != nil {
							event = Event{Type: eventType, Properties: json.RawMessage(data)}
						}
						if event.Type == "" {
							event.Type = eventType
						}

						select {
						case <-ctx.Done():
							return
						case eventCh <- &event:
						}
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

// Health checks the server health.
func (c *Client) Health(ctx context.Context) (*HealthResponse, error) {
	var result HealthResponse
	if err := c.doRequest(ctx, http.MethodGet, "/health", nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// GetMCPServers retrieves the list of MCP servers and their status.
func (c *Client) GetMCPServers(ctx context.Context) (*MCPServersResponse, error) {
	var result MCPServersResponse
	if err := c.doRequest(ctx, http.MethodGet, "/mcp/servers", nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
