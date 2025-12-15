package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// StreamEvent represents an event from SendMessage streaming.
type StreamEvent struct {
	Type    string // "message.updated", "part.updated", etc.
	Message *Message
	Part    *Part
	Raw     json.RawMessage
}

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
