// Package agent provides a Go SDK for the OpenCode-compatible agent server.
//
// This SDK implements the OpenCode API specification.
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

import "time"

// Now returns the current time as a Unix timestamp (float64).
func Now() float64 {
	return float64(time.Now().UnixNano()) / 1e9
}
