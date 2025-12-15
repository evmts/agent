package toast

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/google/uuid"
)

// ToastType represents the type of toast notification
type ToastType string

const (
	ToastInfo    ToastType = "info"
	ToastSuccess ToastType = "success"
	ToastWarning ToastType = "warning"
	ToastError   ToastType = "error"
)

// Toast represents a single toast notification
type Toast struct {
	ID        string
	Message   string
	Type      ToastType
	Duration  time.Duration
	CreatedAt time.Time
}

// Model represents the toast notification manager
type Model struct {
	toasts    []Toast
	width     int
	maxToasts int
}

// New creates a new toast model
func New() Model {
	return Model{
		toasts:    []Toast{},
		width:     80,
		maxToasts: 3,
	}
}

// SetWidth sets the width for toast notifications
func (m *Model) SetWidth(width int) {
	m.width = width
}

// Add adds a new toast notification
func (m *Model) Add(message string, toastType ToastType, duration time.Duration) tea.Cmd {
	toast := Toast{
		ID:        uuid.New().String(),
		Message:   message,
		Type:      toastType,
		Duration:  duration,
		CreatedAt: time.Now(),
	}

	m.toasts = append(m.toasts, toast)

	// Keep only the most recent toasts
	if len(m.toasts) > m.maxToasts {
		m.toasts = m.toasts[len(m.toasts)-m.maxToasts:]
	}

	// Return a command that will remove this toast after its duration
	return m.removeToastAfter(toast.ID, duration)
}

// removeToastAfter returns a command that removes a toast after a duration
func (m *Model) removeToastAfter(id string, duration time.Duration) tea.Cmd {
	return tea.Tick(duration, func(t time.Time) tea.Msg {
		return removeToastMsg{id: id}
	})
}

// removeToastMsg is sent when a toast should be removed
type removeToastMsg struct {
	id string
}

// Update handles messages for the toast model
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case removeToastMsg:
		// Remove the toast with the given ID
		for i, toast := range m.toasts {
			if toast.ID == msg.id {
				m.toasts = append(m.toasts[:i], m.toasts[i+1:]...)
				break
			}
		}
	}
	return m, nil
}

// View renders the toast notifications
func (m Model) View() string {
	if len(m.toasts) == 0 {
		return ""
	}

	var views []string
	for _, toast := range m.toasts {
		views = append(views, renderToast(toast, m.width))
	}

	// Stack toasts vertically with spacing
	result := ""
	for i, view := range views {
		if i > 0 {
			result += "\n"
		}
		result += view
	}

	return result
}

// HasToasts returns true if there are active toasts
func (m Model) HasToasts() bool {
	return len(m.toasts) > 0
}
