package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"agent/tool"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/urfave/cli/v2"
)

var (
	promptStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("12"))

	responseStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10"))

	inputStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.NormalBorder()).
			BorderTop(true).
			BorderBottom(true).
			BorderLeft(false).
			BorderRight(false).
			BorderForeground(lipgloss.Color("240"))

	autocompleteStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("8"))

	autocompleteSelectedStyle = lipgloss.NewStyle().
					Foreground(lipgloss.Color("0")).
					Background(lipgloss.Color("12"))

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))

	availableCommands = []string{"/commit", "/model"}
)

type message struct {
	role         string
	content      string
	toolUseID    string                                 // For tool_result messages
	toolName     string                                 // For displaying tool executions
	isToolUse    bool
	isToolResult bool
	toolUseBlock *anthropic.ContentBlockUnion // Store original tool_use block from Claude
	Error        error
}

type modelOption struct {
	name        string
	description string
	apiModel    anthropic.Model
}

var modelOptions = []modelOption{
	{
		name:        "Default (Sonnet 4.5)",
		description: "Smartest model for daily use",
		apiModel:    anthropic.Model("claude-sonnet-4-5-20250929"),
	},
	{
		name:        "Opus 4.1",
		description: "For complex tasks · Reaches usage limits faster",
		apiModel:    anthropic.Model("claude-opus-4-1-20250805"),
	},
	{
		name:        "Haiku 4.5",
		description: "Fast and lightweight · Most cost-effective",
		apiModel:    anthropic.Model("claude-haiku-4-5-20251001"),
	},
	{
		name:        "Sonnet (1M context)",
		description: "Sonnet 4.5 with 1M context · Uses rate limits faster",
		apiModel:    anthropic.Model("claude-sonnet-4-5-20250929"),
	},
}

type mode string

const (
	normalMode mode = "normal"
	planMode   mode = "plan"
	bypassMode mode = "bypass"
)

var modes = []mode{normalMode, planMode, bypassMode}

type model struct {
	messages              []message
	input                 string
	cursor                int
	apiKey                string
	client                anthropic.Client
	waiting               bool
	err                   error
	width                 int
	height                int
	showAutocomplete      bool
	autocompleteOptions   []string
	autocompleteSelection int
	showModelMenu         bool
	modelMenuSelection    int
	currentModel          anthropic.Model
	currentMode           mode
	toolRegistry          *tool.ToolRegistry
}

func (m model) getCurrentDir() string {
	dir, err := os.Getwd()
	if err != nil {
		return "~"
	}
	return dir
}

type responseMsg string
type errMsg error

func initialModel(apiKey string) model {
	client := anthropic.NewClient(option.WithAPIKey(apiKey))
	return model{
		messages:              []message{},
		input:                 "",
		cursor:                0,
		apiKey:                apiKey,
		client:                client,
		waiting:               false,
		showAutocomplete:      false,
		autocompleteOptions:   []string{},
		autocompleteSelection: 0,
		showModelMenu:         false,
		modelMenuSelection:    0,
		currentModel:          anthropic.Model("claude-sonnet-4-5-20250929"),
		currentMode:           normalMode,
		toolRegistry:          tool.NewToolRegistry(),
	}
}

func filterCommands(input string) []string {
	if !strings.HasPrefix(input, "/") {
		return []string{}
	}

	var matches []string
	for _, cmd := range availableCommands {
		if strings.HasPrefix(cmd, input) {
			matches = append(matches, cmd)
		}
	}
	return matches
}

func (m *model) updateAutocomplete() {
	m.autocompleteOptions = filterCommands(m.input)
	m.showAutocomplete = len(m.autocompleteOptions) > 0
	if m.autocompleteSelection >= len(m.autocompleteOptions) {
		m.autocompleteSelection = 0
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Always allow Ctrl+C to quit, even when waiting
		if msg.Type == tea.KeyCtrlC {
			return m, tea.Quit
		}

		if m.waiting {
			return m, nil
		}

		// Check for alt+enter or option+enter for multiline (before other key handling)
		// Note: Shift+Enter is industry standard but terminals can't reliably detect it
		// so we use Alt+Enter like Claude Code does
		if msg.Type == tea.KeyEnter && msg.Alt {
			m.input += "\n"
			return m, nil
		}

		// Handle model menu navigation
		if m.showModelMenu {
			switch msg.Type {
			case tea.KeyCtrlC, tea.KeyEsc:
				m.showModelMenu = false
				return m, nil

			case tea.KeyEnter:
				selectedModel := modelOptions[m.modelMenuSelection]
				m.currentModel = selectedModel.apiModel
				m.showModelMenu = false
				m.messages = append(m.messages, message{
					role:    "system",
					content: fmt.Sprintf("Set model to %s", selectedModel.name),
				})
				return m, nil

			case tea.KeyUp:
				m.modelMenuSelection--
				if m.modelMenuSelection < 0 {
					m.modelMenuSelection = len(modelOptions) - 1
				}

			case tea.KeyDown:
				m.modelMenuSelection++
				if m.modelMenuSelection >= len(modelOptions) {
					m.modelMenuSelection = 0
				}
			}
			return m, nil
		}

		switch msg.Type {
		case tea.KeyEsc:
			if m.showAutocomplete {
				m.showAutocomplete = false
				return m, nil
			}
			return m, tea.Quit

		case tea.KeyCtrlC:
			return m, tea.Quit

		case tea.KeyEnter:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				// Accept autocomplete suggestion
				m.input = m.autocompleteOptions[m.autocompleteSelection]
				m.showAutocomplete = false
				m.autocompleteSelection = 0
				return m, nil
			}

			if strings.TrimSpace(m.input) == "" {
				return m, nil
			}

			// Check if it's a slash command
			if m.input == "/model" {
				m.showModelMenu = true
				m.input = ""
				return m, nil
			} else if strings.HasPrefix(m.input, "/") {
				m.messages = append(m.messages, message{role: "system", content: "Command: " + m.input})
				m.input = ""
				return m, nil
			}

			userMsg := message{role: "user", content: m.input}
			m.messages = append(m.messages, userMsg)
			input := m.input
			m.input = ""
			m.waiting = true

			return m, func() tea.Msg {
				return sendToClaudeAPIWithTools(m.client, m.currentModel, m.messages, input, m.toolRegistry, m.currentMode)
			}

		case tea.KeyTab:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.input = m.autocompleteOptions[m.autocompleteSelection]
				m.showAutocomplete = false
				m.autocompleteSelection = 0
			}

		case tea.KeyShiftTab:
			// Cycle through modes
			currentIndex := 0
			for i, mode := range modes {
				if mode == m.currentMode {
					currentIndex = i
					break
				}
			}
			nextIndex := (currentIndex + 1) % len(modes)
			m.currentMode = modes[nextIndex]

		case tea.KeyUp:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection--
				if m.autocompleteSelection < 0 {
					m.autocompleteSelection = len(m.autocompleteOptions) - 1
				}
			}

		case tea.KeyDown:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection++
				if m.autocompleteSelection >= len(m.autocompleteOptions) {
					m.autocompleteSelection = 0
				}
			}

		case tea.KeyBackspace:
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
				m.updateAutocomplete()
			}

		case tea.KeySpace:
			m.input += " "
			m.showAutocomplete = false

		case tea.KeyRunes:
			m.input += string(msg.Runes)
			m.updateAutocomplete()
		}

	case responseMsg:
		m.waiting = false
		m.messages = append(m.messages, message{role: "assistant", content: string(msg)})

	case toolUseMsg:
		m.waiting = false
		// Add a message showing the tool is being used
		m.messages = append(m.messages, message{
			role:         "assistant",
			content:      fmt.Sprintf("Using tool: %s", msg.toolName),
			isToolUse:    true,
			toolName:     msg.toolName,
			toolUseID:    msg.toolID,
			toolUseBlock: &msg.toolUseBlock,
		})

		// Execute the tool
		return m, func() tea.Msg {
			result, err := m.toolRegistry.Execute(msg.toolName, msg.input, tool.ToolContext{
				SessionID: "main",
				Abort:     context.Background(),
				Mode:      string(m.currentMode),
			})

			if err != nil {
				result.Error = err
			}

			return toolResultMsg{
				toolName: msg.toolName,
				toolID:   msg.toolID,
				result:   result,
			}
		}

	case toolResultMsg:
		m.waiting = true
		// Add tool result to messages
		resultContent := msg.result.Output
		if resultContent == "" {
			resultContent = "(empty output)"
		}
		m.messages = append(m.messages, message{
			role:         "tool_result",
			content:      resultContent,
			isToolResult: true,
			toolName:     msg.toolName,
			toolUseID:    msg.toolID,
			Error:        msg.result.Error,
		})

		// Continue conversation with tool result - send it back to Claude
		return m, func() tea.Msg {
			return continueWithToolResult(m.client, m.currentModel, m.messages, msg, m.toolRegistry, m.currentMode)
		}

	case errMsg:
		m.waiting = false
		m.err = msg

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	}

	return m, nil
}

func getModelName(apiModel anthropic.Model) string {
	for _, opt := range modelOptions {
		if opt.apiModel == apiModel {
			return opt.name
		}
	}
	return "Default (Sonnet 4.5)"
}

func (m model) View() string {
	var s strings.Builder

	// Display logo header on first render (when no messages)
	if len(m.messages) == 0 && !m.showModelMenu {
		logoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
		versionStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))

		s.WriteString(logoStyle.Render(" ▐▛███▜▌") + "   " + lipgloss.NewStyle().Bold(true).Render("Plue v0.0.0") + "\n")
		s.WriteString(logoStyle.Render("▝▜█████▛▘") + "  " + getModelName(m.currentModel) + "\n")
		s.WriteString(logoStyle.Render("  ▘▘ ▝▝") + "    " + versionStyle.Render(m.getCurrentDir()) + "\n\n")
	}

	// Display model menu if active
	if m.showModelMenu {
		s.WriteString(lipgloss.NewStyle().Bold(true).Render("Switch between Claude models") + "\n\n")
		for i, opt := range modelOptions {
			prefix := "   "
			if i == m.modelMenuSelection {
				prefix = " ❯ "
			}

			checkmark := ""
			if opt.apiModel == m.currentModel {
				checkmark = " ✔"
			}

			line := fmt.Sprintf("%s%d. %-25s %s%s", prefix, i+1, opt.name, opt.description, checkmark)
			if i == m.modelMenuSelection {
				s.WriteString(autocompleteSelectedStyle.Render(line) + "\n")
			} else {
				s.WriteString(line + "\n")
			}
		}
		return s.String()
	}

	// Display chat history
	for _, msg := range m.messages {
		if msg.role == "user" {
			s.WriteString(promptStyle.Render("> ") + msg.content + "\n\n")
		} else if msg.role == "system" {
			s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render(msg.content) + "\n\n")
		} else if msg.isToolUse {
			toolStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("14"))
			s.WriteString(toolStyle.Render("🔧 ") + msg.content + "\n\n")
		} else if msg.isToolResult {
			resultStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
			s.WriteString(resultStyle.Render("  └─ Result: ") + msg.content + "\n\n")
		} else {
			s.WriteString(responseStyle.Render("⏺ ") + msg.content + "\n\n")
		}
	}

	// Display waiting indicator
	if m.waiting {
		s.WriteString(responseStyle.Render("⏺ Thinking...") + "\n\n")
	}

	// Display error if any
	if m.err != nil {
		s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render(fmt.Sprintf("✗ %v", m.err)) + "\n\n")
		m.err = nil
	}

	// Top border
	borderLine := strings.Repeat("─", m.width)
	s.WriteString(borderLine + "\n")

	// Display input box spanning full width (handle multiline)
	inputLines := strings.Split(m.input, "\n")
	for i, line := range inputLines {
		if i == 0 {
			s.WriteString("> " + line + "\n")
		} else {
			s.WriteString("  " + line + "\n")
		}
	}

	// Bottom border
	s.WriteString(borderLine + "\n")

	// Status line
	modeText := ""
	switch m.currentMode {
	case planMode:
		modeText = "plan mode"
	case bypassMode:
		modeText = "bypass permissions"
	default:
		modeText = m.input
		if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
			modeText = m.autocompleteOptions[m.autocompleteSelection]
		}
	}

	statusLeft := "  ⏵⏵ " + modeText
	s.WriteString(statusStyle.Render(statusLeft) + "\n")
	s.WriteString(statusStyle.Render("  (shift+tab to cycle)") + "\n")

	return s.String()
}

func main() {
	app := &cli.App{
		Name:  "agent",
		Usage: "A Claude Code agent with interactive TUI",
		Flags: []cli.Flag{
			&cli.BoolFlag{
				Name:    "interactive",
				Aliases: []string{"i"},
				Usage:   "Run in interactive TUI mode",
			},
		},
		Action: func(c *cli.Context) error {
			if c.Bool("interactive") {
				apiKey := os.Getenv("ANTHROPIC_API_KEY")
				if apiKey == "" {
					return fmt.Errorf("ANTHROPIC_API_KEY environment variable is required")
				}

				p := tea.NewProgram(initialModel(apiKey), tea.WithAltScreen())
				if _, err := p.Run(); err != nil {
					return err
				}
			} else {
				cli.ShowAppHelp(c)
			}
			return nil
		},
	}

	if err := app.Run(os.Args); err != nil {
		log.Fatal(err)
	}
}
