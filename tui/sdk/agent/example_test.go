package agent_test

import (
	"context"
	"fmt"
	"log"

	"github.com/williamcory/agent/sdk/agent"
)

func Example_basicUsage() {
	// Create a client
	client := agent.NewClient("http://localhost:8000")

	ctx := context.Background()

	// Check health
	health, err := client.Health(ctx)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Server status: %s, Agent configured: %v\n", health.Status, health.AgentConfigured)

	// Create a session
	session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
		Title: agent.String("My Chat Session"),
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Created session: %s\n", session.ID)

	// Send a message with streaming
	eventCh, errCh, err := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
		Parts: []interface{}{
			agent.TextPartInput{Type: "text", Text: "Hello, how are you?"},
		},
	})
	if err != nil {
		log.Fatal(err)
	}

	// Process streaming events
	for {
		select {
		case err := <-errCh:
			if err != nil {
				log.Printf("Stream error: %v", err)
			}
			return
		case event, ok := <-eventCh:
			if !ok {
				fmt.Println("Stream completed")
				return
			}

			switch event.Type {
			case "message.updated":
				if event.Message != nil {
					fmt.Printf("Message %s: role=%s\n", event.Message.ID, event.Message.Role)
				}
			case "part.updated":
				if event.Part != nil && event.Part.IsText() {
					fmt.Printf("Text: %s\n", event.Part.Text)
				}
			}
		}
	}
}

func Example_syncMessage() {
	client := agent.NewClient("http://localhost:8000")
	ctx := context.Background()

	// Create session
	session, _ := client.CreateSession(ctx, nil)

	// Send message and wait for complete response
	result, err := client.SendMessageSync(ctx, session.ID, &agent.PromptRequest{
		Parts: []interface{}{
			agent.TextPartInput{Type: "text", Text: "What is 2+2?"},
		},
	})
	if err != nil {
		log.Fatal(err)
	}

	// Print the response
	for _, part := range result.Parts {
		if part.IsText() {
			fmt.Printf("Response: %s\n", part.Text)
		}
	}
}

func Example_globalEvents() {
	client := agent.NewClient("http://localhost:8000")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Subscribe to global events
	eventCh, errCh, err := client.SubscribeToEvents(ctx)
	if err != nil {
		log.Fatal(err)
	}

	// Process events
	for {
		select {
		case err := <-errCh:
			if err != nil {
				log.Printf("Event error: %v", err)
			}
			return
		case event, ok := <-eventCh:
			if !ok {
				return
			}

			switch event.Type {
			case "session.created":
				fmt.Printf("New session: %s\n", event.Session.ID)
			case "session.deleted":
				fmt.Printf("Session deleted: %s\n", event.Session.ID)
			case "message.updated":
				fmt.Printf("Message updated: %s\n", event.Message.ID)
			case "part.updated":
				if event.Part.IsText() {
					fmt.Printf("Text part: %s\n", event.Part.Text)
				}
			}
		}
	}
}

func Example_sessionManagement() {
	client := agent.NewClient("http://localhost:8000")
	ctx := context.Background()

	// List all sessions
	sessions, _ := client.ListSessions(ctx)
	fmt.Printf("Found %d sessions\n", len(sessions))

	// Create a new session
	session, _ := client.CreateSession(ctx, &agent.CreateSessionRequest{
		Title: agent.String("Test Session"),
	})

	// Update the session title
	session, _ = client.UpdateSession(ctx, session.ID, &agent.UpdateSessionRequest{
		Title: agent.String("Updated Title"),
	})

	// Fork the session
	forked, _ := client.ForkSession(ctx, session.ID, nil)
	fmt.Printf("Forked session: %s (parent: %s)\n", forked.ID, *forked.ParentID)

	// Delete sessions
	_ = client.DeleteSession(ctx, forked.ID)
	_ = client.DeleteSession(ctx, session.ID)
}
