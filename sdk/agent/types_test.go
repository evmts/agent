package agent_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/williamcory/agent/sdk/agent"
)

func TestSessionTime(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		now := agent.Now()
		archived := now + 1000

		st := agent.SessionTime{
			Created:  now,
			Updated:  now + 100,
			Archived: &archived,
		}

		data, err := json.Marshal(st)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.SessionTime
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Created != st.Created {
			t.Errorf("Created mismatch: got %v, want %v", decoded.Created, st.Created)
		}
		if decoded.Updated != st.Updated {
			t.Errorf("Updated mismatch: got %v, want %v", decoded.Updated, st.Updated)
		}
		if decoded.Archived == nil || *decoded.Archived != *st.Archived {
			t.Errorf("Archived mismatch: got %v, want %v", decoded.Archived, st.Archived)
		}
	})

	t.Run("omit archived when nil", func(t *testing.T) {
		st := agent.SessionTime{
			Created: agent.Now(),
			Updated: agent.Now(),
		}

		data, err := json.Marshal(st)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("Unmarshal to map error = %v", err)
		}

		if _, exists := m["archived"]; exists {
			t.Error("expected 'archived' to be omitted when nil")
		}
	})
}

func TestFileDiff(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		diff := agent.FileDiff{
			File:      "main.go",
			Before:    "old content\nline 2",
			After:     "new content\nline 2\nline 3",
			Additions: 2,
			Deletions: 1,
		}

		data, err := json.Marshal(diff)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.FileDiff
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.File != diff.File {
			t.Errorf("File mismatch: got %s, want %s", decoded.File, diff.File)
		}
		if decoded.Additions != diff.Additions {
			t.Errorf("Additions mismatch: got %d, want %d", decoded.Additions, diff.Additions)
		}
		if decoded.Deletions != diff.Deletions {
			t.Errorf("Deletions mismatch: got %d, want %d", decoded.Deletions, diff.Deletions)
		}
	})
}

func TestSessionSummary(t *testing.T) {
	t.Run("marshal and unmarshal with diffs", func(t *testing.T) {
		summary := agent.SessionSummary{
			Additions: 10,
			Deletions: 5,
			Files:     2,
			Diffs: []agent.FileDiff{
				{File: "file1.go", Additions: 5, Deletions: 2},
				{File: "file2.go", Additions: 5, Deletions: 3},
			},
		}

		data, err := json.Marshal(summary)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.SessionSummary
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Additions != summary.Additions {
			t.Errorf("Additions mismatch: got %d, want %d", decoded.Additions, summary.Additions)
		}
		if len(decoded.Diffs) != len(summary.Diffs) {
			t.Errorf("Diffs length mismatch: got %d, want %d", len(decoded.Diffs), len(summary.Diffs))
		}
	})
}

func TestSession(t *testing.T) {
	t.Run("marshal and unmarshal complete session", func(t *testing.T) {
		now := agent.Now()
		parentID := "parent-123"

		session := agent.Session{
			ID:        "sess-123",
			ProjectID: "proj-456",
			Directory: "/home/user/project",
			Title:     "My Session",
			Version:   "1.0.0",
			Time: agent.SessionTime{
				Created: now,
				Updated: now,
			},
			ParentID: &parentID,
			Summary: &agent.SessionSummary{
				Additions: 10,
				Deletions: 5,
				Files:     2,
			},
		}

		data, err := json.Marshal(session)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Session
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.ID != session.ID {
			t.Errorf("ID mismatch: got %s, want %s", decoded.ID, session.ID)
		}
		if decoded.Title != session.Title {
			t.Errorf("Title mismatch: got %s, want %s", decoded.Title, session.Title)
		}
		if decoded.ParentID == nil || *decoded.ParentID != *session.ParentID {
			t.Errorf("ParentID mismatch: got %v, want %v", decoded.ParentID, session.ParentID)
		}
	})

	t.Run("omit optional fields", func(t *testing.T) {
		session := agent.Session{
			ID:        "sess-123",
			ProjectID: "proj-456",
			Directory: "/home/user/project",
			Title:     "My Session",
			Version:   "1.0.0",
			Time: agent.SessionTime{
				Created: agent.Now(),
				Updated: agent.Now(),
			},
		}

		data, err := json.Marshal(session)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("Unmarshal to map error = %v", err)
		}

		if _, exists := m["parentID"]; exists {
			t.Error("expected 'parentID' to be omitted when nil")
		}
		if _, exists := m["summary"]; exists {
			t.Error("expected 'summary' to be omitted when nil")
		}
		if _, exists := m["revert"]; exists {
			t.Error("expected 'revert' to be omitted when nil")
		}
	})
}

func TestModelInfo(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		model := agent.ModelInfo{
			ProviderID: "anthropic",
			ModelID:    "claude-3-5-sonnet-20241022",
		}

		data, err := json.Marshal(model)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.ModelInfo
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.ProviderID != model.ProviderID {
			t.Errorf("ProviderID mismatch: got %s, want %s", decoded.ProviderID, model.ProviderID)
		}
		if decoded.ModelID != model.ModelID {
			t.Errorf("ModelID mismatch: got %s, want %s", decoded.ModelID, model.ModelID)
		}
	})
}

func TestTokenInfo(t *testing.T) {
	t.Run("marshal and unmarshal with cache", func(t *testing.T) {
		tokens := agent.TokenInfo{
			Input:     100,
			Output:    200,
			Reasoning: 50,
			Cache: map[string]int{
				"read":  1000,
				"write": 500,
			},
		}

		data, err := json.Marshal(tokens)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.TokenInfo
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Input != tokens.Input {
			t.Errorf("Input mismatch: got %d, want %d", decoded.Input, tokens.Input)
		}
		if decoded.Output != tokens.Output {
			t.Errorf("Output mismatch: got %d, want %d", decoded.Output, tokens.Output)
		}
		if decoded.Cache["read"] != tokens.Cache["read"] {
			t.Errorf("Cache read mismatch: got %d, want %d", decoded.Cache["read"], tokens.Cache["read"])
		}
	})

	t.Run("omit cache when nil", func(t *testing.T) {
		tokens := agent.TokenInfo{
			Input:  100,
			Output: 200,
		}

		data, err := json.Marshal(tokens)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("Unmarshal to map error = %v", err)
		}

		if _, exists := m["cache"]; exists {
			t.Error("expected 'cache' to be omitted when nil")
		}
	})
}

func TestMessage(t *testing.T) {
	t.Run("user message", func(t *testing.T) {
		msg := agent.Message{
			ID:        "msg-user-123",
			SessionID: "sess-456",
			Role:      "user",
			Time: agent.MessageTime{
				Created: agent.Now(),
			},
			Agent: "test-agent",
			Model: &agent.ModelInfo{
				ProviderID: "anthropic",
				ModelID:    "claude-3-5-sonnet-20241022",
			},
		}

		if !msg.IsUser() {
			t.Error("expected IsUser() to return true")
		}
		if msg.IsAssistant() {
			t.Error("expected IsAssistant() to return false")
		}

		data, err := json.Marshal(msg)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Message
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsUser() {
			t.Error("decoded message should be user message")
		}
		if decoded.ID != msg.ID {
			t.Errorf("ID mismatch: got %s, want %s", decoded.ID, msg.ID)
		}
	})

	t.Run("assistant message", func(t *testing.T) {
		completedTime := agent.Now()
		finishReason := "end_turn"

		msg := agent.Message{
			ID:         "msg-assistant-123",
			SessionID:  "sess-456",
			Role:       "assistant",
			ParentID:   "msg-user-123",
			ModelID:    "claude-3-5-sonnet-20241022",
			ProviderID: "anthropic",
			Mode:       "normal",
			Time: agent.MessageTime{
				Created:   agent.Now(),
				Completed: &completedTime,
			},
			Path: &agent.PathInfo{
				Cwd:  "/home/user/project",
				Root: "/home/user",
			},
			Cost: 0.001,
			Tokens: &agent.TokenInfo{
				Input:  100,
				Output: 200,
			},
			Finish: &finishReason,
		}

		if msg.IsUser() {
			t.Error("expected IsUser() to return false")
		}
		if !msg.IsAssistant() {
			t.Error("expected IsAssistant() to return true")
		}

		data, err := json.Marshal(msg)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Message
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsAssistant() {
			t.Error("decoded message should be assistant message")
		}
		if decoded.Cost != msg.Cost {
			t.Errorf("Cost mismatch: got %f, want %f", decoded.Cost, msg.Cost)
		}
		if decoded.Finish == nil || *decoded.Finish != *msg.Finish {
			t.Errorf("Finish mismatch: got %v, want %v", decoded.Finish, msg.Finish)
		}
	})

	t.Run("message with error", func(t *testing.T) {
		errorData := json.RawMessage(`{"message": "test error", "code": "error_code"}`)

		msg := agent.Message{
			ID:        "msg-123",
			SessionID: "sess-456",
			Role:      "assistant",
			Time: agent.MessageTime{
				Created: agent.Now(),
			},
			Error: errorData,
		}

		data, err := json.Marshal(msg)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Message
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		// Compare the actual error content, not the formatting
		var originalError map[string]interface{}
		var decodedError map[string]interface{}

		if err := json.Unmarshal(msg.Error, &originalError); err != nil {
			t.Fatalf("Unmarshal original error: %v", err)
		}
		if err := json.Unmarshal(decoded.Error, &decodedError); err != nil {
			t.Fatalf("Unmarshal decoded error: %v", err)
		}

		if originalError["message"] != decodedError["message"] || originalError["code"] != decodedError["code"] {
			t.Errorf("Error content mismatch: got %v, want %v", decodedError, originalError)
		}
	})
}

func TestPart(t *testing.T) {
	t.Run("text part", func(t *testing.T) {
		now := agent.Now()
		end := now + 1.5

		part := agent.Part{
			ID:        "part-123",
			SessionID: "sess-456",
			MessageID: "msg-789",
			Type:      "text",
			Text:      "Hello, world!",
			Time: &agent.PartTime{
				Start: now,
				End:   &end,
			},
		}

		if !part.IsText() {
			t.Error("expected IsText() to return true")
		}
		if part.IsReasoning() || part.IsTool() || part.IsFile() {
			t.Error("expected other type checks to return false")
		}

		data, err := json.Marshal(part)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Part
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsText() {
			t.Error("decoded part should be text type")
		}
		if decoded.Text != part.Text {
			t.Errorf("Text mismatch: got %s, want %s", decoded.Text, part.Text)
		}
	})

	t.Run("reasoning part", func(t *testing.T) {
		part := agent.Part{
			ID:        "part-123",
			SessionID: "sess-456",
			MessageID: "msg-789",
			Type:      "reasoning",
			Text:      "Let me think about this...",
			Time: &agent.PartTime{
				Start: agent.Now(),
			},
		}

		if !part.IsReasoning() {
			t.Error("expected IsReasoning() to return true")
		}

		data, err := json.Marshal(part)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Part
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsReasoning() {
			t.Error("decoded part should be reasoning type")
		}
	})

	t.Run("tool part", func(t *testing.T) {
		part := agent.Part{
			ID:        "part-123",
			SessionID: "sess-456",
			MessageID: "msg-789",
			Type:      "tool",
			Tool:      "Read",
			State: &agent.ToolState{
				Status: "completed",
				Input: map[string]interface{}{
					"file_path": "/path/to/file.txt",
				},
				Output: "File contents here",
				Time: &agent.PartTime{
					Start: agent.Now(),
				},
			},
		}

		if !part.IsTool() {
			t.Error("expected IsTool() to return true")
		}

		data, err := json.Marshal(part)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Part
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsTool() {
			t.Error("decoded part should be tool type")
		}
		if decoded.Tool != part.Tool {
			t.Errorf("Tool mismatch: got %s, want %s", decoded.Tool, part.Tool)
		}
		if decoded.State == nil {
			t.Fatal("expected non-nil state")
		}
		if decoded.State.Status != part.State.Status {
			t.Errorf("State.Status mismatch: got %s, want %s", decoded.State.Status, part.State.Status)
		}
	})

	t.Run("file part", func(t *testing.T) {
		filename := "document.pdf"

		part := agent.Part{
			ID:        "part-123",
			SessionID: "sess-456",
			MessageID: "msg-789",
			Type:      "file",
			Mime:      "application/pdf",
			URL:       "https://example.com/file.pdf",
			Filename:  &filename,
		}

		if !part.IsFile() {
			t.Error("expected IsFile() to return true")
		}

		data, err := json.Marshal(part)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Part
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if !decoded.IsFile() {
			t.Error("decoded part should be file type")
		}
		if decoded.Mime != part.Mime {
			t.Errorf("Mime mismatch: got %s, want %s", decoded.Mime, part.Mime)
		}
		if decoded.URL != part.URL {
			t.Errorf("URL mismatch: got %s, want %s", decoded.URL, part.URL)
		}
		if decoded.Filename == nil || *decoded.Filename != *part.Filename {
			t.Errorf("Filename mismatch: got %v, want %v", decoded.Filename, part.Filename)
		}
	})
}

func TestToolState(t *testing.T) {
	t.Run("pending state", func(t *testing.T) {
		state := agent.ToolState{
			Status: "pending",
			Input: map[string]interface{}{
				"command": "ls -la",
			},
		}

		data, err := json.Marshal(state)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.ToolState
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Status != "pending" {
			t.Errorf("Status mismatch: got %s, want pending", decoded.Status)
		}
	})

	t.Run("running state with metadata", func(t *testing.T) {
		title := "Running command"

		state := agent.ToolState{
			Status: "running",
			Input: map[string]interface{}{
				"command": "npm install",
			},
			Raw:   "npm install",
			Title: &title,
			Metadata: map[string]interface{}{
				"pid":       12345,
				"startTime": agent.Now(),
			},
			Time: &agent.PartTime{
				Start: agent.Now(),
			},
		}

		data, err := json.Marshal(state)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.ToolState
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Status != "running" {
			t.Errorf("Status mismatch: got %s, want running", decoded.Status)
		}
		if decoded.Title == nil || *decoded.Title != *state.Title {
			t.Errorf("Title mismatch: got %v, want %v", decoded.Title, state.Title)
		}
		if decoded.Metadata["pid"].(float64) != 12345 {
			t.Error("Metadata pid mismatch")
		}
	})

	t.Run("completed state with output", func(t *testing.T) {
		state := agent.ToolState{
			Status: "completed",
			Input: map[string]interface{}{
				"file_path": "/test/file.txt",
			},
			Output: "File contents here\nLine 2\nLine 3",
		}

		data, err := json.Marshal(state)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.ToolState
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Status != "completed" {
			t.Errorf("Status mismatch: got %s, want completed", decoded.Status)
		}
		if decoded.Output != state.Output {
			t.Errorf("Output mismatch: got %s, want %s", decoded.Output, state.Output)
		}
	})
}

func TestMessageWithParts(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		msg := agent.MessageWithParts{
			Info: agent.Message{
				ID:        "msg-123",
				SessionID: "sess-456",
				Role:      "assistant",
				Time: agent.MessageTime{
					Created: agent.Now(),
				},
			},
			Parts: []agent.Part{
				{
					ID:        "part-1",
					SessionID: "sess-456",
					MessageID: "msg-123",
					Type:      "text",
					Text:      "Hello",
				},
				{
					ID:        "part-2",
					SessionID: "sess-456",
					MessageID: "msg-123",
					Type:      "text",
					Text:      " world!",
				},
			},
		}

		data, err := json.Marshal(msg)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.MessageWithParts
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Info.ID != msg.Info.ID {
			t.Errorf("Info.ID mismatch: got %s, want %s", decoded.Info.ID, msg.Info.ID)
		}
		if len(decoded.Parts) != len(msg.Parts) {
			t.Errorf("Parts length mismatch: got %d, want %d", len(decoded.Parts), len(msg.Parts))
		}
	})
}

func TestEvent(t *testing.T) {
	t.Run("session event", func(t *testing.T) {
		sessionEvent := agent.SessionEvent{
			Info: agent.Session{
				ID:        "sess-123",
				ProjectID: "proj-456",
				Directory: "/test",
				Title:     "Test",
				Version:   "1.0.0",
				Time: agent.SessionTime{
					Created: agent.Now(),
					Updated: agent.Now(),
				},
			},
		}

		eventData, err := json.Marshal(sessionEvent)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		event := agent.Event{
			Type:       "session.created",
			Properties: eventData,
		}

		data, err := json.Marshal(event)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Event
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Type != event.Type {
			t.Errorf("Type mismatch: got %s, want %s", decoded.Type, event.Type)
		}

		// Decode the properties
		var decodedSessionEvent agent.SessionEvent
		if err := json.Unmarshal(decoded.Properties, &decodedSessionEvent); err != nil {
			t.Fatalf("Unmarshal properties error = %v", err)
		}

		if decodedSessionEvent.Info.ID != sessionEvent.Info.ID {
			t.Errorf("Session ID mismatch: got %s, want %s", decodedSessionEvent.Info.ID, sessionEvent.Info.ID)
		}
	})

	t.Run("message event", func(t *testing.T) {
		messageEvent := agent.MessageEvent{
			Info: agent.Message{
				ID:        "msg-123",
				SessionID: "sess-456",
				Role:      "user",
				Time: agent.MessageTime{
					Created: agent.Now(),
				},
			},
		}

		eventData, err := json.Marshal(messageEvent)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		event := agent.Event{
			Type:       "message.updated",
			Properties: eventData,
		}

		data, err := json.Marshal(event)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.Event
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		var decodedMessageEvent agent.MessageEvent
		if err := json.Unmarshal(decoded.Properties, &decodedMessageEvent); err != nil {
			t.Fatalf("Unmarshal properties error = %v", err)
		}

		if decodedMessageEvent.Info.ID != messageEvent.Info.ID {
			t.Errorf("Message ID mismatch: got %s, want %s", decodedMessageEvent.Info.ID, messageEvent.Info.ID)
		}
	})
}

func TestRequestTypes(t *testing.T) {
	t.Run("CreateSessionRequest", func(t *testing.T) {
		req := agent.CreateSessionRequest{
			ParentID: agent.String("parent-123"),
			Title:    agent.String("My Session"),
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.CreateSessionRequest
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.ParentID == nil || *decoded.ParentID != *req.ParentID {
			t.Errorf("ParentID mismatch: got %v, want %v", decoded.ParentID, req.ParentID)
		}
		if decoded.Title == nil || *decoded.Title != *req.Title {
			t.Errorf("Title mismatch: got %v, want %v", decoded.Title, req.Title)
		}
	})

	t.Run("PromptRequest with text", func(t *testing.T) {
		req := agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: "Hello, world!"},
			},
			MessageID: agent.String("msg-123"),
			Model: &agent.ModelInfo{
				ProviderID: "anthropic",
				ModelID:    "claude-3-5-sonnet-20241022",
			},
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.PromptRequest
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if len(decoded.Parts) != len(req.Parts) {
			t.Errorf("Parts length mismatch: got %d, want %d", len(decoded.Parts), len(req.Parts))
		}
	})

	t.Run("PromptRequest with file", func(t *testing.T) {
		req := agent.PromptRequest{
			Parts: []interface{}{
				agent.FilePartInput{
					Type:     "file",
					Mime:     "application/pdf",
					URL:      "https://example.com/doc.pdf",
					Filename: agent.String("document.pdf"),
				},
			},
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.PromptRequest
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if len(decoded.Parts) != 1 {
			t.Fatalf("expected 1 part, got %d", len(decoded.Parts))
		}

		// Parts are decoded as map[string]interface{}
		part := decoded.Parts[0].(map[string]interface{})
		if part["type"] != "file" {
			t.Errorf("expected type 'file', got %v", part["type"])
		}
		if part["mime"] != "application/pdf" {
			t.Errorf("expected mime 'application/pdf', got %v", part["mime"])
		}
	})

	t.Run("ForkRequest", func(t *testing.T) {
		req := agent.ForkRequest{
			MessageID: agent.String("msg-123"),
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.ForkRequest
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.MessageID == nil || *decoded.MessageID != *req.MessageID {
			t.Errorf("MessageID mismatch: got %v, want %v", decoded.MessageID, req.MessageID)
		}
	})

	t.Run("RevertRequest", func(t *testing.T) {
		req := agent.RevertRequest{
			MessageID: "msg-123",
			PartID:    agent.String("part-456"),
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.RevertRequest
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.MessageID != req.MessageID {
			t.Errorf("MessageID mismatch: got %s, want %s", decoded.MessageID, req.MessageID)
		}
		if decoded.PartID == nil || *decoded.PartID != *req.PartID {
			t.Errorf("PartID mismatch: got %v, want %v", decoded.PartID, req.PartID)
		}
	})
}

func TestHelperFunctions(t *testing.T) {
	t.Run("String helper", func(t *testing.T) {
		s := agent.String("test")
		if s == nil {
			t.Fatal("expected non-nil pointer")
		}
		if *s != "test" {
			t.Errorf("expected 'test', got %s", *s)
		}
	})

	t.Run("Bool helper", func(t *testing.T) {
		b := agent.Bool(true)
		if b == nil {
			t.Fatal("expected non-nil pointer")
		}
		if !*b {
			t.Error("expected true")
		}
	})

	t.Run("Now helper", func(t *testing.T) {
		now := agent.Now()
		if now <= 0 {
			t.Error("expected positive timestamp")
		}

		// Should be close to current time
		goNow := float64(time.Now().UnixNano()) / 1e9
		diff := goNow - now
		if diff < 0 {
			diff = -diff
		}
		if diff > 1.0 { // Allow 1 second difference
			t.Errorf("Now() returned timestamp too far from current time: diff = %f", diff)
		}
	})
}

func TestRevertInfo(t *testing.T) {
	t.Run("complete revert info", func(t *testing.T) {
		snapshot := "snapshot-data"
		diff := "diff-data"

		info := agent.RevertInfo{
			MessageID: "msg-123",
			PartID:    agent.String("part-456"),
			Snapshot:  &snapshot,
			Diff:      &diff,
		}

		data, err := json.Marshal(info)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.RevertInfo
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.MessageID != info.MessageID {
			t.Errorf("MessageID mismatch: got %s, want %s", decoded.MessageID, info.MessageID)
		}
		if decoded.PartID == nil || *decoded.PartID != *info.PartID {
			t.Errorf("PartID mismatch: got %v, want %v", decoded.PartID, info.PartID)
		}
		if decoded.Snapshot == nil || *decoded.Snapshot != *info.Snapshot {
			t.Errorf("Snapshot mismatch: got %v, want %v", decoded.Snapshot, info.Snapshot)
		}
		if decoded.Diff == nil || *decoded.Diff != *info.Diff {
			t.Errorf("Diff mismatch: got %v, want %v", decoded.Diff, info.Diff)
		}
	})
}

func TestPathInfo(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		path := agent.PathInfo{
			Cwd:  "/home/user/project",
			Root: "/home/user",
		}

		data, err := json.Marshal(path)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.PathInfo
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Cwd != path.Cwd {
			t.Errorf("Cwd mismatch: got %s, want %s", decoded.Cwd, path.Cwd)
		}
		if decoded.Root != path.Root {
			t.Errorf("Root mismatch: got %s, want %s", decoded.Root, path.Root)
		}
	})
}

func TestMessageTime(t *testing.T) {
	t.Run("with completed time", func(t *testing.T) {
		created := agent.Now()
		completed := created + 5.5

		mt := agent.MessageTime{
			Created:   created,
			Completed: &completed,
		}

		data, err := json.Marshal(mt)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.MessageTime
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Created != mt.Created {
			t.Errorf("Created mismatch: got %v, want %v", decoded.Created, mt.Created)
		}
		if decoded.Completed == nil || *decoded.Completed != *mt.Completed {
			t.Errorf("Completed mismatch: got %v, want %v", decoded.Completed, mt.Completed)
		}
	})

	t.Run("without completed time", func(t *testing.T) {
		mt := agent.MessageTime{
			Created: agent.Now(),
		}

		data, err := json.Marshal(mt)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("Unmarshal to map error = %v", err)
		}

		if _, exists := m["completed"]; exists {
			t.Error("expected 'completed' to be omitted when nil")
		}
	})
}

func TestPartTime(t *testing.T) {
	t.Run("with end time", func(t *testing.T) {
		start := agent.Now()
		end := start + 2.5

		pt := agent.PartTime{
			Start: start,
			End:   &end,
		}

		data, err := json.Marshal(pt)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.PartTime
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Start != pt.Start {
			t.Errorf("Start mismatch: got %v, want %v", decoded.Start, pt.Start)
		}
		if decoded.End == nil || *decoded.End != *pt.End {
			t.Errorf("End mismatch: got %v, want %v", decoded.End, pt.End)
		}
	})

	t.Run("without end time", func(t *testing.T) {
		pt := agent.PartTime{
			Start: agent.Now(),
		}

		data, err := json.Marshal(pt)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("Unmarshal to map error = %v", err)
		}

		if _, exists := m["end"]; exists {
			t.Error("expected 'end' to be omitted when nil")
		}
	})
}

func TestHealthResponse(t *testing.T) {
	t.Run("marshal and unmarshal", func(t *testing.T) {
		health := agent.HealthResponse{
			Status:          "ok",
			AgentConfigured: true,
		}

		data, err := json.Marshal(health)
		if err != nil {
			t.Fatalf("Marshal() error = %v", err)
		}

		var decoded agent.HealthResponse
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal() error = %v", err)
		}

		if decoded.Status != health.Status {
			t.Errorf("Status mismatch: got %s, want %s", decoded.Status, health.Status)
		}
		if decoded.AgentConfigured != health.AgentConfigured {
			t.Errorf("AgentConfigured mismatch: got %v, want %v", decoded.AgentConfigured, health.AgentConfigured)
		}
	})
}
