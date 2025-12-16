package chat

import "github.com/williamcory/agent/sdk/agent"

// StartAssistantMessage starts a new assistant message for streaming
func (m *Model) StartAssistantMessage() {
	m.currentParts = make(map[string]agent.Part)
	m.currentMessage = nil
	m.streamingPartID = ""

	m.messages = append(m.messages, Message{
		Role:        RoleAssistant,
		Parts:       []agent.Part{},
		IsStreaming: true,
	})
}

// HandleStreamEvent processes a streaming event from the SDK
func (m *Model) HandleStreamEvent(event *agent.StreamEvent) {
	if event == nil {
		return
	}

	switch event.Type {
	case "message.updated":
		if event.Message != nil {
			m.currentMessage = event.Message
			// Update the last message's info
			if len(m.messages) > 0 {
				m.messages[len(m.messages)-1].Info = event.Message
			}
		}

	case "part.updated":
		if event.Part != nil {
			m.currentParts[event.Part.ID] = *event.Part

			// Track streaming text part
			if event.Part.IsText() {
				m.streamingPartID = event.Part.ID
			}

			// Rebuild parts for the current message
			m.rebuildCurrentMessageParts()
		}
	}

	m.updateContent()
}

// rebuildCurrentMessageParts rebuilds the parts slice from the map
func (m *Model) rebuildCurrentMessageParts() {
	if len(m.messages) == 0 {
		return
	}

	// Convert map to slice, maintaining some order
	var parts []agent.Part
	for _, part := range m.currentParts {
		parts = append(parts, part)
	}

	m.messages[len(m.messages)-1].Parts = parts
}

// EndAssistantMessage marks the current assistant message as complete
func (m *Model) EndAssistantMessage() {
	if len(m.messages) > 0 {
		m.messages[len(m.messages)-1].IsStreaming = false
	}
	m.streamingPartID = ""
	m.updateContent()
}
