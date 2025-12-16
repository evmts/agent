package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/williamcory/agent/tui/internal/app"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/muesli/termenv"
)

func main() {
	// Disable terminal queries that leak escape sequences
	termenv.SetDefaultOutput(termenv.NewOutput(os.Stdout, termenv.WithProfile(termenv.TrueColor)))

	backendURL := flag.String("backend", "http://localhost:8000", "Backend server URL")
	flag.Parse()

	p := tea.NewProgram(
		app.New(*backendURL),
		tea.WithAltScreen(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
