# Notification Sound

<metadata>
  <priority>low</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/app/, tui/internal/config/</affects>
</metadata>

## Objective

Play an audio notification when the agent completes a response, alerting users who may have switched to another window.

<context>
Long-running agent operations can take minutes. Users often switch to other tasks while waiting. Claude Code plays a subtle notification sound when:
- A response is complete
- An error occurs that needs attention
- A confirmation is required

This allows users to multitask efficiently without constantly checking the terminal.
</context>

## Requirements

<functional-requirements>
1. Play terminal bell or audio file when:
   - Response streaming completes
   - Error occurs during operation
   - User action is required (confirmation dialog)
2. Settings to configure:
   - Enable/disable sounds
   - Volume level (if using audio files)
   - Sound type (bell, chime, custom)
3. Respect system "Do Not Disturb" mode
4. Option for visual-only notification (flash terminal)
5. Different sounds for success vs error
</functional-requirements>

<technical-requirements>
1. Implement terminal bell (\a escape sequence)
2. Optional: Use system audio APIs for custom sounds
3. Add notification preferences to settings
4. Debounce notifications (don't spam sounds)
5. Detect if terminal is in foreground (skip if focused)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/notification/sound.go` - Notification sound handling
- `tui/internal/config/preferences.go` - Sound preferences
- `tui/internal/app/update.go` - Trigger notifications on events
- `tui/internal/components/dialog/settings.go` - Add sound settings
</files-to-modify>

<notification-system>
```go
package notification

import (
    "fmt"
    "os"
    "os/exec"
    "runtime"
)

type SoundType int

const (
    SoundBell SoundType = iota
    SoundChime
    SoundError
    SoundCustom
)

type NotificationConfig struct {
    Enabled     bool
    SoundType   SoundType
    Volume      float64  // 0.0 to 1.0
    CustomPath  string   // For custom sound files
    VisualFlash bool     // Flash terminal instead of sound
}

func PlayNotification(soundType SoundType, config NotificationConfig) error {
    if !config.Enabled {
        return nil
    }

    if config.VisualFlash {
        return flashTerminal()
    }

    switch soundType {
    case SoundBell:
        return playBell()
    case SoundChime, SoundError:
        return playSystemSound(soundType, config.Volume)
    case SoundCustom:
        return playCustomSound(config.CustomPath, config.Volume)
    }

    return nil
}

func playBell() error {
    // Terminal bell escape sequence
    fmt.Print("\a")
    return nil
}

func flashTerminal() error {
    // Visual bell - invert colors briefly
    fmt.Print("\033[?5h")  // Enable reverse video
    time.Sleep(100 * time.Millisecond)
    fmt.Print("\033[?5l")  // Disable reverse video
    return nil
}

func playSystemSound(soundType SoundType, volume float64) error {
    switch runtime.GOOS {
    case "darwin":
        // Use afplay on macOS
        soundFile := "/System/Library/Sounds/Glass.aiff"
        if soundType == SoundError {
            soundFile = "/System/Library/Sounds/Basso.aiff"
        }
        return exec.Command("afplay", "-v", fmt.Sprintf("%.1f", volume), soundFile).Run()

    case "linux":
        // Use paplay or aplay
        return exec.Command("paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga").Run()

    case "windows":
        // Use PowerShell to play system sound
        sound := "Asterisk"
        if soundType == SoundError {
            sound = "Hand"
        }
        return exec.Command("powershell", "-c",
            fmt.Sprintf("[System.Media.SystemSounds]::%s.Play()", sound)).Run()
    }

    return nil
}
```
</notification-system>

<event-triggers>
```go
// In app/update.go

func (m Model) handleStreamingComplete() (Model, tea.Cmd) {
    m.state = StateIdle
    m.chat.EndAssistantMessage()

    // Play completion sound if enabled
    var cmds []tea.Cmd
    if m.notificationConfig.Enabled {
        cmds = append(cmds, func() tea.Msg {
            notification.PlayNotification(notification.SoundChime, m.notificationConfig)
            return nil
        })
    }

    return m, tea.Batch(cmds...)
}

func (m Model) handleError(err error) (Model, tea.Cmd) {
    m.state = StateError
    m.err = err

    // Play error sound
    if m.notificationConfig.Enabled {
        notification.PlayNotification(notification.SoundError, m.notificationConfig)
    }

    return m, nil
}
```
</event-triggers>

<settings-ui>
```
┌─ Settings ──────────────────────────────────────────┐
│                                                     │
│ Notifications                                       │
│ ─────────────────────────────────────────────────── │
│                                                     │
│ [✓] Enable notification sounds                      │
│                                                     │
│ Sound type:                                         │
│   (•) Terminal bell (works everywhere)              │
│   ( ) System chime (macOS/Linux/Windows)            │
│   ( ) Custom sound file                             │
│   ( ) Visual flash only (no sound)                  │
│                                                     │
│ When to notify:                                     │
│   [✓] Response complete                             │
│   [✓] Error occurred                                │
│   [✓] Confirmation needed                           │
│   [ ] Every tool completion                         │
│                                                     │
│ Volume: [████████░░] 80%                            │
│                                                     │
│ [ ] Only notify when terminal unfocused             │
│                                                     │
└─────────────────────────────────────────────────────┘
```
</settings-ui>

## Acceptance Criteria

<criteria>
- [ ] Terminal bell plays on response completion
- [ ] Different sound for errors
- [ ] Setting to enable/disable sounds
- [ ] Setting to choose sound type
- [ ] Visual flash option for silent environments
- [ ] Volume control (for system sounds)
- [ ] Sounds don't spam (debounced)
- [ ] Works on macOS, Linux, and Windows
- [ ] Settings persist across sessions
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test notification sounds on your OS
4. Rename this file from `13-notification-sound.md` to `13-notification-sound.complete.md`
</completion>
