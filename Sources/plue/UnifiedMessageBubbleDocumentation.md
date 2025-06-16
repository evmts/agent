# Unified Message Bubble Component Documentation

## Overview

The `UnifiedMessageBubbleView` is a highly configurable, reusable message bubble component that consolidates the different message bubble implementations across the Plue codebase. It provides a consistent API while allowing for style customization to match different contexts (chat, agent, terminal, etc.).

## Key Features

- **Protocol-based**: Works with any message type that conforms to `UnifiedMessage`
- **Multiple preset styles**: Professional, Compact, Minimal, Terminal, Display
- **Fully customizable**: Every visual aspect can be configured
- **Theme-aware**: Supports light and dark themes
- **Accessible**: Includes text selection, proper contrast ratios
- **Animated**: Optional smooth animations for appearance and interactions
- **Interactive**: Support for tap handlers and active state highlighting

## Basic Usage

### 1. Make your message type conform to UnifiedMessage

```swift
// The protocol is already implemented for PromptMessage and AgentMessage
// For custom types:
struct MyMessage: UnifiedMessage {
    let id: String
    let content: String
    let timestamp: Date
    let senderType: MessageSenderType
    let metadata: MessageMetadata?
}
```

### 2. Use the component with a preset style

```swift
UnifiedMessageBubbleView(
    message: message,
    style: .professional,  // or .compact, .minimal, .terminal, .display
    theme: appState.currentTheme
)
```

### 3. Add interaction handling

```swift
UnifiedMessageBubbleView(
    message: message,
    style: .professional,
    isActive: activeMessageId == message.id,
    theme: appState.currentTheme,
    onTap: { tappedMessage in
        // Handle message tap
        activeMessageId = tappedMessage.id
    }
)
```

## Preset Styles

### Professional (Default)
- Large avatars (36px) with icon and text
- Generous padding and spacing
- Smooth animations
- Best for: Main chat interfaces, customer-facing UIs

### Compact
- Smaller avatars (28px) with text only
- Reduced padding
- No animations
- Best for: Agent views, dense information displays

### Minimal
- Tiny avatars (24px) with icons
- Minimal padding
- Maximum width constraint
- Best for: Secondary displays, sidebars

### Terminal
- Monospace fonts
- Dark background
- No animations
- Best for: System logs, code output

### Display
- Extra large avatars (48px)
- Large fonts
- Maximum width for readability
- Best for: Presentations, demos

## Custom Styles

Create a custom style by instantiating `MessageBubbleStyle`:

```swift
let customStyle = MessageBubbleStyle(
    avatarSize: 32,
    avatarStyle: .iconWithText,
    bubbleCornerRadius: 16,
    bubblePadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
    maxBubbleWidth: 600,
    contentFont: .system(size: 15),
    timestampFont: .system(size: 11),
    metadataFont: .system(size: 10),
    avatarSpacing: 10,
    timestampSpacing: 6,
    metadataSpacing: 4,
    userBubbleBackground: Color.blue,
    assistantBubbleBackground: Color(NSColor.controlBackgroundColor),
    systemBubbleBackground: Color.gray.opacity(0.1),
    errorBubbleBackground: Color.red.opacity(0.1),
    showAnimations: true,
    animationDuration: 0.25
)
```

## Avatar Styles

The component supports four avatar styles:

1. **`.icon`** - Shows only the icon
2. **`.text`** - Shows only text (initials or abbreviation)
3. **`.iconWithText`** - Shows icon for non-user, "YOU" for user
4. **`.custom(Image)`** - Use a custom image

## Message Types

The component handles different sender types with appropriate styling:

- **User**: Primary color, right-aligned, no border
- **Assistant**: Surface color, left-aligned, subtle border
- **System**: Muted colors, informational appearance
- **Workflow**: Success colors, indicates automation
- **Error**: Error colors, stands out for attention

## Metadata Display

The component can display optional metadata below messages:

```swift
MessageMetadata(
    worktree: "feature-branch",
    workflow: "build-test",
    containerId: "abc123",
    exitCode: 0,
    duration: 12.5,
    promptSnapshot: nil
)
```

## Migration Guide

### From ProfessionalMessageBubbleView

```swift
// Old:
ProfessionalMessageBubbleView(
    message: message,
    isActive: isActive,
    theme: theme
)

// New:
UnifiedMessageBubbleView(
    message: message,
    style: .professional,
    isActive: isActive,
    theme: theme
)
```

### From AgentMessageBubbleView

```swift
// Old:
AgentMessageBubbleView(message: message)

// New:
UnifiedMessageBubbleView(
    message: message,
    style: .compact,
    theme: .dark
)
```

### From MessageBubbleView (Legacy)

```swift
// Old:
MessageBubbleView(
    message: message,
    onAIMessageTapped: { message in
        // Handle tap
    }
)

// New:
UnifiedMessageBubbleView(
    message: message,
    style: .minimal,
    theme: .dark,
    onTap: { message in
        if message.senderType != .user {
            // Handle tap
        }
    }
)
```

## Complete Message List Example

```swift
struct UnifiedChatView: View {
    let messages: [PromptMessage]
    let isProcessing: Bool
    @State private var activeMessageId: String? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(messages) { message in
                        UnifiedMessageBubbleView(
                            message: message,
                            style: .professional,
                            isActive: activeMessageId == message.id,
                            theme: .dark,
                            onTap: { tappedMessage in
                                withAnimation {
                                    activeMessageId = tappedMessage.id
                                }
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .id(message.id)
                    }
                    
                    if isProcessing {
                        UnifiedTypingIndicatorView(style: .professional)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }
                }
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
}
```

## Performance Considerations

- Use `LazyVStack` for long message lists
- Disable animations (`.showAnimations: false`) for better performance with many messages
- Consider using `.compact` or `.minimal` styles for dense displays
- The component uses `@ViewBuilder` and is optimized for SwiftUI's diffing

## Accessibility

- All text is selectable via `.textSelection(.enabled)`
- Colors are chosen for appropriate contrast ratios
- Avatar icons provide visual distinction between sender types
- Timestamps and metadata use semantic font sizes

## Future Enhancements

Potential areas for extension:

1. **Rich content support**: Images, code blocks, links
2. **Reactions**: Emoji reactions on messages
3. **Threading**: Reply indicators and thread views
4. **Status indicators**: Sent, delivered, read receipts
5. **Swipe actions**: Reply, delete, edit gestures
6. **Voice messages**: Audio player integration
7. **Markdown rendering**: Rich text formatting

## Testing

The component includes comprehensive previews. Run the preview provider to see all styles:

```bash
# In Xcode
# Open UnifiedMessageBubbleView.swift
# Click the Preview button
```