package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"claude-tui/internal/app"
	"claude-tui/internal/mock"
)

func main() {
	// Parse flags
	mockServer := flag.Bool("mock", false, "Run the mock server instead of the TUI")
	mockPort := flag.Int("mock-port", 8000, "Port for the mock server")
	backendURL := flag.String("backend", "", "Backend URL (default: http://localhost:8000)")
	flag.Parse()

	// Run mock server if requested
	if *mockServer {
		server := mock.NewServer(*mockPort)
		if err := server.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "Mock server error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Determine backend URL
	url := *backendURL
	if url == "" {
		url = os.Getenv("BACKEND_URL")
	}
	if url == "" {
		url = "http://localhost:8000"
	}

	// Get working directory for the SDK
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting working directory: %v\n", err)
		os.Exit(1)
	}

	// Create SDK client
	client := agent.NewClient(url,
		agent.WithDirectory(cwd),
		agent.WithTimeout(60*time.Second),
	)

	// Create app model
	model := app.New(client)

	// Create program with options
	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	// Set program reference for SSE callbacks
	model.SetProgram(p)

	// Run the TUI
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
