package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/app"
	"tui/internal/embedded"
)

func main() {
	// Parse flags
	backendURL := flag.String("backend", "", "Backend URL (overrides embedded server)")
	useEmbedded := flag.Bool("embedded", true, "Use embedded server (default: true)")
	flag.Parse()

	// Determine backend URL
	url := *backendURL
	if url == "" {
		url = os.Getenv("BACKEND_URL")
	}

	var serverProcess *embedded.ServerProcess
	var cleanup func()

	// If no external backend specified and embedded mode is enabled, start embedded server
	if url == "" && *useEmbedded {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		fmt.Println("Starting embedded server...")
		var err error
		serverProcess, url, err = embedded.StartServer(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error starting embedded server: %v\n", err)
			fmt.Fprintf(os.Stderr, "Tip: Use --backend=URL to connect to an external server\n")
			os.Exit(1)
		}

		cleanup = func() {
			if serverProcess != nil {
				serverProcess.Stop()
			}
		}

		// Handle signals for cleanup
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			<-sigChan
			cleanup()
			os.Exit(0)
		}()

		fmt.Printf("Embedded server running at %s\n", url)
	} else if url == "" {
		url = "http://localhost:8000"
	}

	// Get working directory for the SDK
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting working directory: %v\n", err)
		if cleanup != nil {
			cleanup()
		}
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
		if cleanup != nil {
			cleanup()
		}
		os.Exit(1)
	}

	// Cleanup on normal exit
	if cleanup != nil {
		cleanup()
	}
}
