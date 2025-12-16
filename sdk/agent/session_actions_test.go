package agent_test

import (
	"context"
	"testing"

	"github.com/williamcory/agent/sdk/agent"
)

func TestSessionActions(t *testing.T) {
	srv := newTestServer()
	defer srv.Close()

	client := agent.NewClient(srv.URL())
	ctx := context.Background()

	t.Run("abort session", func(t *testing.T) {
		session, err := client.CreateSession(ctx, nil)
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		err = client.AbortSession(ctx, session.ID)
		if err != nil {
			t.Fatalf("AbortSession() error = %v", err)
		}
	})

	t.Run("get session diff", func(t *testing.T) {
		session, err := client.CreateSession(ctx, nil)
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		diffs, err := client.GetSessionDiff(ctx, session.ID, nil)
		if err != nil {
			t.Fatalf("GetSessionDiff() error = %v", err)
		}

		if len(diffs) == 0 {
			t.Error("expected at least one diff")
		}

		if diffs[0].File == "" {
			t.Error("expected non-empty file name")
		}
	})

	t.Run("fork session", func(t *testing.T) {
		session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Parent Session"),
		})
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		forked, err := client.ForkSession(ctx, session.ID, nil)
		if err != nil {
			t.Fatalf("ForkSession() error = %v", err)
		}

		if forked.ID == session.ID {
			t.Error("forked session should have different ID")
		}

		if forked.ParentID == nil || *forked.ParentID != session.ID {
			t.Errorf("expected parent ID %s, got %v", session.ID, forked.ParentID)
		}
	})

	t.Run("revert and unrevert session", func(t *testing.T) {
		session, err := client.CreateSession(ctx, nil)
		if err != nil {
			t.Fatalf("CreateSession() error = %v", err)
		}

		// Revert
		reverted, err := client.RevertSession(ctx, session.ID, &agent.RevertRequest{
			MessageID: "msg_123",
			PartID:    agent.String("part_456"),
		})
		if err != nil {
			t.Fatalf("RevertSession() error = %v", err)
		}

		if reverted.Revert == nil {
			t.Fatal("expected revert info")
		}
		if reverted.Revert.MessageID != "msg_123" {
			t.Errorf("expected message ID 'msg_123', got %s", reverted.Revert.MessageID)
		}

		// Unrevert
		unreverted, err := client.UnrevertSession(ctx, session.ID)
		if err != nil {
			t.Fatalf("UnrevertSession() error = %v", err)
		}

		if unreverted.Revert != nil {
			t.Error("expected nil revert info after unrevert")
		}
	})
}
