package mock

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type Server struct {
	port int
}

func NewServer(port int) *Server {
	return &Server{port: port}
}

func (s *Server) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.healthHandler)
	mux.HandleFunc("/chat", s.chatHandler)

	addr := fmt.Sprintf(":%d", s.port)
	fmt.Printf("Mock server starting on http://localhost%s\n", addr)
	return http.ListenAndServe(addr, mux)
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"status":           "ok",
		"agent_configured": true,
	})
}

func (s *Server) chatHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse request
	var req struct {
		Message        string  `json:"message"`
		ConversationID *string `json:"conversation_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Set SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "SSE not supported", http.StatusInternalServerError)
		return
	}

	// Generate a mock response based on the input
	s.generateMockResponse(w, flusher, req.Message)
}

func (s *Server) generateMockResponse(w http.ResponseWriter, flusher http.Flusher, userMessage string) {
	lowerMsg := strings.ToLower(userMessage)

	// Simulate different tool uses based on keywords
	if strings.Contains(lowerMsg, "read") || strings.Contains(lowerMsg, "file") {
		s.simulateFileRead(w, flusher)
	} else if strings.Contains(lowerMsg, "run") || strings.Contains(lowerMsg, "command") || strings.Contains(lowerMsg, "execute") {
		s.simulateBashCommand(w, flusher)
	} else if strings.Contains(lowerMsg, "search") || strings.Contains(lowerMsg, "find") {
		s.simulateSearch(w, flusher)
	}

	// Stream the main response
	response := s.getMockResponse(userMessage)
	s.streamTokens(w, flusher, response)

	// Send done event
	sendEvent(w, flusher, "done", map[string]any{
		"conversation_id": "mock-conv-" + fmt.Sprintf("%d", time.Now().UnixNano()),
	})
}

func (s *Server) simulateFileRead(w http.ResponseWriter, flusher http.Flusher) {
	sendEvent(w, flusher, "tool_use", map[string]any{
		"tool": "Read",
		"input": map[string]any{
			"file_path": "/example/main.go",
		},
	})
	time.Sleep(300 * time.Millisecond)

	sendEvent(w, flusher, "tool_result", map[string]any{
		"tool":   "Read",
		"output": "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello, World!\")\n}",
	})
	time.Sleep(100 * time.Millisecond)
}

func (s *Server) simulateBashCommand(w http.ResponseWriter, flusher http.Flusher) {
	sendEvent(w, flusher, "tool_use", map[string]any{
		"tool": "Bash",
		"input": map[string]any{
			"command": "ls -la",
		},
	})
	time.Sleep(400 * time.Millisecond)

	sendEvent(w, flusher, "tool_result", map[string]any{
		"tool":   "Bash",
		"output": "total 16\ndrwxr-xr-x  5 user  staff   160 Dec 14 10:00 .\ndrwxr-xr-x  3 user  staff    96 Dec 14 09:00 ..\n-rw-r--r--  1 user  staff   156 Dec 14 10:00 main.go\n-rw-r--r--  1 user  staff    45 Dec 14 09:30 go.mod",
	})
	time.Sleep(100 * time.Millisecond)
}

func (s *Server) simulateSearch(w http.ResponseWriter, flusher http.Flusher) {
	sendEvent(w, flusher, "tool_use", map[string]any{
		"tool": "Grep",
		"input": map[string]any{
			"pattern": "func main",
			"path":    ".",
		},
	})
	time.Sleep(350 * time.Millisecond)

	sendEvent(w, flusher, "tool_result", map[string]any{
		"tool":   "Grep",
		"output": "main.go:5:func main() {",
	})
	time.Sleep(100 * time.Millisecond)
}

func (s *Server) getMockResponse(userMessage string) string {
	lowerMsg := strings.ToLower(userMessage)

	if strings.Contains(lowerMsg, "hello") || strings.Contains(lowerMsg, "hi") {
		return "Hello! I'm your AI coding assistant. How can I help you today? I can:\n\n- Read and analyze files\n- Execute shell commands\n- Search through your codebase\n- Help with code reviews and refactoring\n\nWhat would you like to work on?"
	}

	if strings.Contains(lowerMsg, "read") || strings.Contains(lowerMsg, "file") {
		return "I've read the file for you. Here's what I found:\n\n```go\npackage main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello, World!\")\n}\n```\n\nThis is a simple Go program that prints \"Hello, World!\" to the console. Would you like me to modify it or explain any part of it?"
	}

	if strings.Contains(lowerMsg, "run") || strings.Contains(lowerMsg, "command") {
		return "I've executed the command. The output shows the contents of the current directory. I can see:\n\n- `main.go` - Your main Go source file\n- `go.mod` - Go module definition\n\nWould you like me to do anything with these files?"
	}

	if strings.Contains(lowerMsg, "search") || strings.Contains(lowerMsg, "find") {
		return "I found the search results! The pattern `func main` appears in `main.go` at line 5. This is the entry point of your Go program.\n\nWould you like me to:\n1. Show the full file content?\n2. Search for something else?\n3. Modify this function?"
	}

	// Default response
	return "I understand your request. Let me help you with that.\n\nI'm a coding assistant that can:\n- **Read files** - Just ask me to look at any file\n- **Run commands** - I can execute shell commands\n- **Search code** - Find patterns in your codebase\n- **Edit code** - Make changes to your files\n\nWhat would you like me to do?"
}

func (s *Server) streamTokens(w http.ResponseWriter, flusher http.Flusher, response string) {
	// Stream character by character for a realistic effect
	// But batch them for efficiency
	batchSize := 3
	runes := []rune(response)

	for i := 0; i < len(runes); i += batchSize {
		end := i + batchSize
		if end > len(runes) {
			end = len(runes)
		}

		chunk := string(runes[i:end])
		sendEvent(w, flusher, "token", map[string]any{
			"content": chunk,
		})

		// Variable delay for more natural feel
		delay := 15 * time.Millisecond
		if chunk == "\n" || chunk == "." || chunk == "!" || chunk == "?" {
			delay = 50 * time.Millisecond
		}
		time.Sleep(delay)
	}
}

func sendEvent(w http.ResponseWriter, flusher http.Flusher, event string, data any) {
	jsonData, _ := json.Marshal(data)
	fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, jsonData)
	flusher.Flush()
}
