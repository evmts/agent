package agent_test

import (
	"context"
	"testing"

	"github.com/williamcory/agent/sdk/agent"
)

func TestSessionOperations(t *testing.T) {
	srv := newTestServer()
	defer srv.Close()

	client := agent.NewClient(srv.URL())
	ctx := context.Background()

	t.Run("create session", func(t *testing.T) {
		session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Test Session"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		if session.ID == "" {
			t.Error("expected non-empty session ID")
		}
		if session.Title != "Test Session" {
			t.Errorf("expected title 'Test Session', got %s", session.Title)
		}
	})

	t.Run("create session with defaults", func(t *testing.T) {
		session, err := client.CreateSession(ctx, nil)
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		if session.ID == "" {
			t.Error("expected non-empty session ID")
		}
	})

	t.Run("list sessions", func(t *testing.T) {
		// Create a session first
		_, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("List Test"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		sessions, err := client.ListSessions(ctx)
		if err != nil {
			t.Fatalf("ListSessions() error = %v", err)
		}

		if len(sessions) == 0 {
			t.Error("expected at least one session")
		}
	})

	t.Run("get session", func(t *testing.T) {
		created, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Get Test"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		session, err := client.GetSession(ctx, created.ID)
		if err != nil {
			t.Fatalf("GetSession() error = %v", err)
		}

		if session.ID != created.ID {
			t.Errorf("expected session ID %s, got %s", created.ID, session.ID)
		}
		if session.Title != "Get Test" {
			t.Errorf("expected title 'Get Test', got %s", session.Title)
		}
	})

	t.Run("update session", func(t *testing.T) {
		created, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Original Title"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		updated, err := client.UpdateSession(ctx, created.ID, &agent.UpdateSessionRequest{
			Title: agent.String("Updated Title"),
		})
		if err != nil {
			t.Fatalf("UpdateSession() error = %v", err)
		}

		if updated.Title != "Updated Title" {
			t.Errorf("expected title 'Updated Title', got %s", updated.Title)
		}
	})

	t.Run("delete session", func(t *testing.T) {
		created, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Delete Test"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		err = client.DeleteSession(ctx, created.ID)
		if err != nil {
			t.Fatalf("DeleteSession() error = %v", err)
		}

		// Verify it's gone
		_, err = client.GetSession(ctx, created.ID)
		if err == nil {
			t.Error("expected error when getting deleted session")
		}
	})

	t.Run("get non-existent session", func(t *testing.T) {
		_, err := client.GetSession(ctx, "nonexistent")
		if err == nil {
			t.Error("expected error for non-existent session")
		}
	})
}
