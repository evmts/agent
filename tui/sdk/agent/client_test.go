package agent_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/williamcory/agent/sdk/agent"
)

// testServer is a mock server that implements the OpenCode API for testing
type testServer struct {
	server       *httptest.Server
	sessions     map[string]*agent.Session
	messages     map[string]map[string]*agent.MessageWithParts // sessionID -> messageID -> message
	mu           sync.RWMutex
	eventClients []chan *agent.Event
}

func newTestServer() *testServer {
	ts := &testServer{
		sessions:     make(map[string]*agent.Session),
		messages:     make(map[string]map[string]*agent.MessageWithParts),
		eventClients: make([]chan *agent.Event, 0),
	}

	mux := http.NewServeMux()

	// Health endpoint
	mux.HandleFunc("/health", ts.handleHealth)

	// Session endpoints
	mux.HandleFunc("/session", ts.handleSessions)
	mux.HandleFunc("/session/", ts.handleSession)

	// Global events
	mux.HandleFunc("/global/event", ts.handleGlobalEvents)

	ts.server = httptest.NewServer(mux)
	return ts
}

func (ts *testServer) Close() {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	for _, ch := range ts.eventClients {
		close(ch)
	}
	ts.server.Close()
}

func (ts *testServer) URL() string {
	return ts.server.URL
}

func (ts *testServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(agent.HealthResponse{
		Status:          "ok",
		AgentConfigured: true,
	})
}

func (ts *testServer) handleSessions(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		ts.listSessions(w, r)
	case http.MethodPost:
		ts.createSession(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (ts *testServer) listSessions(w http.ResponseWriter, r *http.Request) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	sessions := make([]agent.Session, 0, len(ts.sessions))
	for _, sess := range ts.sessions {
		sessions = append(sessions, *sess)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

func (ts *testServer) createSession(w http.ResponseWriter, r *http.Request) {
	var req agent.CreateSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ts.mu.Lock()
	defer ts.mu.Unlock()

	now := agent.Now()
	session := &agent.Session{
		ID:        fmt.Sprintf("sess_%d", len(ts.sessions)+1),
		ProjectID: "test-project",
		Directory: "/test/dir",
		Title:     "Test Session",
		Version:   "1.0.0",
		Time: agent.SessionTime{
			Created: now,
			Updated: now,
		},
	}

	if req.Title != nil {
		session.Title = *req.Title
	}
	if req.ParentID != nil {
		session.ParentID = req.ParentID
	}

	ts.sessions[session.ID] = session
	ts.messages[session.ID] = make(map[string]*agent.MessageWithParts)

	// Broadcast session.created event
	ts.broadcastEvent(&agent.Event{
		Type:       "session.created",
		Properties: ts.mustMarshal(agent.SessionEvent{Info: *session}),
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(session)
}

func (ts *testServer) handleSession(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/session/")
	parts := strings.Split(path, "/")

	if len(parts) == 0 || parts[0] == "" {
		http.Error(w, "invalid session ID", http.StatusBadRequest)
		return
	}

	sessionID := parts[0]

	// Single session operations
	if len(parts) == 1 {
		switch r.Method {
		case http.MethodGet:
			ts.getSession(w, r, sessionID)
		case http.MethodDelete:
			ts.deleteSession(w, r, sessionID)
		case http.MethodPatch:
			ts.updateSession(w, r, sessionID)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
		return
	}

	// Sub-resource operations
	resource := parts[1]
	switch resource {
	case "message":
		ts.handleMessages(w, r, sessionID, parts[2:])
	case "abort":
		ts.abortSession(w, r, sessionID)
	case "diff":
		ts.getSessionDiff(w, r, sessionID)
	case "fork":
		ts.forkSession(w, r, sessionID)
	case "revert":
		ts.revertSession(w, r, sessionID)
	case "unrevert":
		ts.unrevertSession(w, r, sessionID)
	default:
		http.Error(w, "not found", http.StatusNotFound)
	}
}

func (ts *testServer) getSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	session, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(session)
}

func (ts *testServer) deleteSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	session, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	delete(ts.sessions, sessionID)
	delete(ts.messages, sessionID)

	// Broadcast session.deleted event
	ts.broadcastEvent(&agent.Event{
		Type:       "session.deleted",
		Properties: ts.mustMarshal(agent.SessionEvent{Info: *session}),
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(true)
}

func (ts *testServer) updateSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	var req agent.UpdateSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ts.mu.Lock()
	defer ts.mu.Unlock()

	session, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	if req.Title != nil {
		session.Title = *req.Title
	}
	session.Time.Updated = agent.Now()

	// Broadcast session.updated event
	ts.broadcastEvent(&agent.Event{
		Type:       "session.updated",
		Properties: ts.mustMarshal(agent.SessionEvent{Info: *session}),
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(session)
}

func (ts *testServer) abortSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	if _, ok := ts.sessions[sessionID]; !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(true)
}

func (ts *testServer) getSessionDiff(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	if _, ok := ts.sessions[sessionID]; !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	diffs := []agent.FileDiff{
		{
			File:      "test.go",
			Before:    "old content",
			After:     "new content",
			Additions: 1,
			Deletions: 1,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(diffs)
}

func (ts *testServer) forkSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	var req agent.ForkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ts.mu.Lock()
	defer ts.mu.Unlock()

	parent, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	now := agent.Now()
	forked := &agent.Session{
		ID:        fmt.Sprintf("sess_fork_%d", len(ts.sessions)+1),
		ProjectID: parent.ProjectID,
		Directory: parent.Directory,
		Title:     parent.Title + " (fork)",
		Version:   parent.Version,
		ParentID:  &sessionID,
		Time: agent.SessionTime{
			Created: now,
			Updated: now,
		},
	}

	ts.sessions[forked.ID] = forked
	ts.messages[forked.ID] = make(map[string]*agent.MessageWithParts)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(forked)
}

func (ts *testServer) revertSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	var req agent.RevertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ts.mu.Lock()
	defer ts.mu.Unlock()

	session, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	session.Revert = &agent.RevertInfo{
		MessageID: req.MessageID,
		PartID:    req.PartID,
	}
	session.Time.Updated = agent.Now()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(session)
}

func (ts *testServer) unrevertSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	session, ok := ts.sessions[sessionID]
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	session.Revert = nil
	session.Time.Updated = agent.Now()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(session)
}

func (ts *testServer) handleMessages(w http.ResponseWriter, r *http.Request, sessionID string, parts []string) {
	ts.mu.RLock()
	_, ok := ts.sessions[sessionID]
	ts.mu.RUnlock()

	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	// List or create message
	if len(parts) == 0 || parts[0] == "" {
		switch r.Method {
		case http.MethodGet:
			ts.listMessages(w, r, sessionID)
		case http.MethodPost:
			ts.sendMessage(w, r, sessionID)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
		return
	}

	// Get specific message
	messageID := parts[0]
	if r.Method == http.MethodGet {
		ts.getMessage(w, r, sessionID, messageID)
	} else {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (ts *testServer) listMessages(w http.ResponseWriter, r *http.Request, sessionID string) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	sessionMessages := ts.messages[sessionID]
	messages := make([]agent.MessageWithParts, 0, len(sessionMessages))
	for _, msg := range sessionMessages {
		messages = append(messages, *msg)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

func (ts *testServer) getMessage(w http.ResponseWriter, r *http.Request, sessionID, messageID string) {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	msg, ok := ts.messages[sessionID][messageID]
	if !ok {
		http.Error(w, "message not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(msg)
}

func (ts *testServer) sendMessage(w http.ResponseWriter, r *http.Request, sessionID string) {
	// Check if this is a streaming request
	accept := r.Header.Get("Accept")
	if accept == "text/event-stream" {
		ts.sendMessageStreaming(w, r, sessionID)
		return
	}

	http.Error(w, "streaming required", http.StatusBadRequest)
}

func (ts *testServer) sendMessageStreaming(w http.ResponseWriter, r *http.Request, sessionID string) {
	var req agent.PromptRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Set SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	// Create user message
	now := agent.Now()
	userMsgID := fmt.Sprintf("msg_user_%d", time.Now().UnixNano())
	userMsg := &agent.MessageWithParts{
		Info: agent.Message{
			ID:        userMsgID,
			SessionID: sessionID,
			Role:      "user",
			Time: agent.MessageTime{
				Created: now,
			},
			Agent: "test-agent",
		},
		Parts: []agent.Part{},
	}

	// Store user message
	ts.mu.Lock()
	if ts.messages[sessionID] == nil {
		ts.messages[sessionID] = make(map[string]*agent.MessageWithParts)
	}
	ts.messages[sessionID][userMsgID] = userMsg
	ts.mu.Unlock()

	// Create assistant message
	assistantMsgID := fmt.Sprintf("msg_assistant_%d", time.Now().UnixNano())
	assistantMsg := agent.Message{
		ID:         assistantMsgID,
		SessionID:  sessionID,
		Role:       "assistant",
		ParentID:   userMsgID,
		ModelID:    "claude-3-5-sonnet-20241022",
		ProviderID: "anthropic",
		Mode:       "normal",
		Time: agent.MessageTime{
			Created: now,
		},
		Path: &agent.PathInfo{
			Cwd:  "/test/dir",
			Root: "/test",
		},
		Cost: 0.001,
		Tokens: &agent.TokenInfo{
			Input:  10,
			Output: 20,
		},
	}

	// Send message.updated event wrapped in Event structure
	messageEventData, _ := json.Marshal(agent.MessageEvent{Info: assistantMsg})
	event := map[string]interface{}{
		"type":       "message.updated",
		"properties": json.RawMessage(messageEventData),
	}
	eventJSON, _ := json.Marshal(event)
	fmt.Fprintf(w, "data: %s\n\n", string(eventJSON))
	flusher.Flush()

	// Simulate streaming text parts
	partID := fmt.Sprintf("part_%d", time.Now().UnixNano())
	textParts := []string{"Hello", " there", "!", " How", " can", " I", " help", " you", "?"}
	fullText := ""

	for _, chunk := range textParts {
		fullText += chunk
		part := agent.Part{
			ID:        partID,
			SessionID: sessionID,
			MessageID: assistantMsgID,
			Type:      "text",
			Text:      fullText,
			Time: &agent.PartTime{
				Start: now,
			},
		}

		partData, _ := json.Marshal(part)
		partEvent := map[string]interface{}{
			"type":       "part.updated",
			"properties": json.RawMessage(partData),
		}
		partEventJSON, _ := json.Marshal(partEvent)
		fmt.Fprintf(w, "data: %s\n\n", string(partEventJSON))
		flusher.Flush()
		time.Sleep(10 * time.Millisecond) // Simulate streaming delay
	}

	// Mark part as complete
	endTime := agent.Now()
	finalPart := agent.Part{
		ID:        partID,
		SessionID: sessionID,
		MessageID: assistantMsgID,
		Type:      "text",
		Text:      fullText,
		Time: &agent.PartTime{
			Start: now,
			End:   &endTime,
		},
	}

	// Store the completed message
	ts.mu.Lock()
	ts.messages[sessionID][assistantMsgID] = &agent.MessageWithParts{
		Info:  assistantMsg,
		Parts: []agent.Part{finalPart},
	}
	ts.mu.Unlock()

	partData, _ := json.Marshal(finalPart)
	finalPartEvent := map[string]interface{}{
		"type":       "part.updated",
		"properties": json.RawMessage(partData),
	}
	finalPartEventJSON, _ := json.Marshal(finalPartEvent)
	fmt.Fprintf(w, "data: %s\n\n", string(finalPartEventJSON))
	flusher.Flush()

	// Complete the message
	completedTime := agent.Now()
	assistantMsg.Time.Completed = &completedTime
	finishReason := "end_turn"
	assistantMsg.Finish = &finishReason

	finalMessageEventData, _ := json.Marshal(agent.MessageEvent{Info: assistantMsg})
	finalEvent := map[string]interface{}{
		"type":       "message.updated",
		"properties": json.RawMessage(finalMessageEventData),
	}
	finalEventJSON, _ := json.Marshal(finalEvent)
	fmt.Fprintf(w, "data: %s\n\n", string(finalEventJSON))
	flusher.Flush()
}

func (ts *testServer) handleGlobalEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Set SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	// Create event channel for this client
	eventCh := make(chan *agent.Event, 10)

	ts.mu.Lock()
	ts.eventClients = append(ts.eventClients, eventCh)
	ts.mu.Unlock()

	// Send events to client
	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-eventCh:
			if !ok {
				return
			}
			eventJSON, _ := json.Marshal(event)
			fmt.Fprintf(w, "data: %s\n\n", string(eventJSON))
			flusher.Flush()
		}
	}
}

func (ts *testServer) broadcastEvent(event *agent.Event) {
	for _, ch := range ts.eventClients {
		select {
		case ch <- event:
		default:
			// Skip if channel is full
		}
	}
}

func (ts *testServer) mustMarshal(v interface{}) json.RawMessage {
	data, _ := json.Marshal(v)
	return data
}

// Tests

func TestNewClient(t *testing.T) {
	t.Run("basic client creation", func(t *testing.T) {
		client := agent.NewClient("http://localhost:8000")
		if client == nil {
			t.Fatal("expected non-nil client")
		}
	})

	t.Run("client with options", func(t *testing.T) {
		httpClient := &http.Client{Timeout: 10 * time.Second}
		client := agent.NewClient("http://localhost:8000",
			agent.WithHTTPClient(httpClient),
			agent.WithDirectory("/test/dir"),
			agent.WithTimeout(5*time.Second),
		)
		if client == nil {
			t.Fatal("expected non-nil client")
		}
	})

	t.Run("URL normalization", func(t *testing.T) {
		client := agent.NewClient("http://localhost:8000/")
		if client == nil {
			t.Fatal("expected non-nil client")
		}
	})
}

func TestHealth(t *testing.T) {
	srv := newTestServer()
	defer srv.Close()

	client := agent.NewClient(srv.URL())
	ctx := context.Background()

	health, err := client.Health(ctx)
	if err != nil {
		t.Fatalf("Health() error = %v", err)
	}

	if health.Status != "ok" {
		t.Errorf("expected status 'ok', got %s", health.Status)
	}

	if !health.AgentConfigured {
		t.Error("expected agent_configured to be true")
	}
}
