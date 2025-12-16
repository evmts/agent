package agent_test

import (
	"context"
	"testing"
	"time"

	"github.com/williamcory/agent/sdk/agent"
)

func TestMessageOperations(t *testing.T) {
	srv := newTestServer()
	defer srv.Close()

	client := agent.NewClient(srv.URL())
	ctx := context.Background()

	// Create a session for message tests
	session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
		Title: agent.String("Message Test Session"),
	})
	if err != nil {
		t.Fatalf("CreateSession() error = %v", err)
	}

	t.Run("send message streaming", func(t *testing.T) {
		eventCh, errCh, err := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: "Hello, world!"},
			},
		})
		if err != nil {
			t.Fatalf("SendMessage() error = %v", err)
		}

		receivedEvents := 0
		receivedParts := false
		receivedMessage := false

		done := false
		for !done {
			select {
			case err := <-errCh:
				if err != nil {
					t.Fatalf("stream error = %v", err)
				}
				done = true
			case event, ok := <-eventCh:
				if !ok {
					done = true
					break
				}

				receivedEvents++

				switch event.Type {
				case "message.updated":
					receivedMessage = true
					if event.Message != nil && !event.Message.IsAssistant() {
						t.Error("expected assistant message")
					}
				case "part.updated":
					receivedParts = true
					if event.Part != nil && !event.Part.IsText() {
						t.Error("expected text part")
					}
				}
			case <-time.After(5 * time.Second):
				t.Fatal("timeout waiting for events")
			}
		}

		if receivedEvents == 0 {
			t.Error("expected to receive events")
		}
		if !receivedParts {
			t.Error("expected to receive part events")
		}
		if !receivedMessage {
			t.Error("expected to receive message events")
		}
	})

	t.Run("send message sync", func(t *testing.T) {
		result, err := client.SendMessageSync(ctx, session.ID, &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: "What is 2+2?"},
			},
		})
		if err != nil {
			t.Fatalf("SendMessageSync() error = %v", err)
		}

		if result.Info.ID == "" {
			t.Error("expected non-empty message ID")
		}

		if !result.Info.IsAssistant() {
			t.Error("expected assistant message")
		}

		if len(result.Parts) == 0 {
			t.Error("expected at least one part")
		}

		if !result.Parts[0].IsText() {
			t.Error("expected text part")
		}

		if result.Parts[0].Text == "" {
			t.Error("expected non-empty text")
		}
	})

	t.Run("list messages", func(t *testing.T) {
		// Send a message first
		_, err := client.SendMessageSync(ctx, session.ID, &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: "Test message"},
			},
		})
		if err != nil {
			t.Fatalf("SendMessageSync() error = %v", err)
		}

		messages, err := client.ListMessages(ctx, session.ID, nil)
		if err != nil {
			t.Fatalf("ListMessages() error = %v", err)
		}

		if len(messages) == 0 {
			t.Error("expected at least one message")
		}
	})

	t.Run("get message", func(t *testing.T) {
		// Send a message first
		sent, err := client.SendMessageSync(ctx, session.ID, &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: "Get test"},
			},
		})
		if err != nil {
			t.Fatalf("SendMessageSync() error = %v", err)
		}

		msg, err := client.GetMessage(ctx, session.ID, sent.Info.ID)
		if err != nil {
			t.Fatalf("GetMessage() error = %v", err)
		}

		if msg.Info.ID != sent.Info.ID {
			t.Errorf("expected message ID %s, got %s", sent.Info.ID, msg.Info.ID)
		}
	})
}

func TestStreamingCancellation(t *testing.T) {
	srv := newTestServer()
	defer srv.Close()

	client := agent.NewClient(srv.URL())

	session, err := client.CreateSession(context.Background(), nil)
	if err != nil {
		t.Fatalf("CreateSession() error = %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	eventCh, errCh, err := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
		Parts: []interface{}{
			agent.TextPartInput{Type: "text", Text: "Hello"},
		},
	})
	if err != nil {
		t.Fatalf("SendMessage() error = %v", err)
	}

	// Receive one event then cancel
	select {
	case <-eventCh:
		cancel()
	case err := <-errCh:
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timeout waiting for event")
	}

	// Wait for error channel to report context cancellation
	select {
	case err := <-errCh:
		if err != context.Canceled {
			t.Errorf("expected context.Canceled, got %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for cancellation error")
	}

	// Give the SSE goroutine time to clean up
	time.Sleep(100 * time.Millisecond)
}
