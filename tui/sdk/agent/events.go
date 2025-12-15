package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
)

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
