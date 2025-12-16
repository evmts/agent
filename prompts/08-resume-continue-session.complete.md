# Resume/Continue Session

<metadata>
  <priority>medium</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/app/</affects>
</metadata>

## Objective

Implement a "continue where you left off" feature that prompts users to resume their last session when starting the TUI.

<context>
Claude Code remembers the last active session and offers to continue it on startup. This provides continuity for:
- Long-running development tasks
- Multi-day projects
- Interrupted sessions

Users shouldn't have to manually find and select their previous session every time they start the agent.
</context>

## Requirements

<functional-requirements>
1. On startup, detect if there's a recent session (< 24 hours old)
2. Show prompt: "Continue previous session? (last active 2 hours ago)"
3. Options:
   - [Y] Yes, continue - Load the session
   - [N] No, new session - Create fresh session
   - [S] Select session - Show session list
4. Remember preference: "Always continue" / "Always ask" / "Always new"
5. Show session preview (title, message count, last message snippet)
6. Skip prompt if last session is too old or completed
</functional-requirements>

<technical-requirements>
1. Store last session ID in local config
2. Add startup flow before main UI loads
3. Create `ResumeDialog` component
4. Add preference to settings
5. Handle missing/deleted sessions gracefully
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/app/app.go` - Add startup resume check
- `tui/internal/components/dialog/resume.go` - Resume prompt dialog
- `tui/internal/config/preferences.go` - Store resume preferences
- `tui/internal/app/update.go` - Handle resume flow
</files-to-modify>

<session-resume-logic>
```go
type ResumePreference string

const (
    ResumeAlwaysAsk      ResumePreference = "ask"
    ResumeAlwaysContinue ResumePreference = "continue"
    ResumeAlwaysNew      ResumePreference = "new"
)

type LastSessionInfo struct {
    SessionID    string
    Title        string
    LastActive   time.Time
    MessageCount int
    LastMessage  string  // Truncated preview
}

func (m Model) checkResumeSession() tea.Cmd {
    return func() tea.Msg {
        // Load last session info from config
        info := loadLastSessionInfo()
        if info == nil {
            return noResumeAvailableMsg{}
        }

        // Check if session is recent enough (< 24 hours)
        if time.Since(info.LastActive) > 24*time.Hour {
            return noResumeAvailableMsg{}
        }

        // Check preference
        pref := loadResumePreference()
        switch pref {
        case ResumeAlwaysContinue:
            return resumeSessionMsg{sessionID: info.SessionID}
        case ResumeAlwaysNew:
            return createNewSessionMsg{}
        default:
            return showResumeDialogMsg{info: info}
        }
    }
}
```
</session-resume-logic>

<example-ui>
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              Continue previous session?             │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ 📝 Implementing user authentication           │  │
│  │                                               │  │
│  │ Last active: 2 hours ago                      │  │
│  │ Messages: 47                                  │  │
│  │                                               │  │
│  │ Last message:                                 │  │
│  │ "The JWT implementation is complete. Would    │  │
│  │  you like me to add refresh token support?"   │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│      [Y] Continue    [N] New    [S] Select          │
│                                                     │
│  ☐ Remember my choice                               │
│                                                     │
└─────────────────────────────────────────────────────┘
```
</example-ui>

<startup-flow>
```
┌─────────────────┐
│   App Starts    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Load last       │
│ session info    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     No      ┌─────────────────┐
│ Recent session? │────────────▶│ Create new      │
│ (< 24 hours)    │             │ session         │
└────────┬────────┘             └─────────────────┘
         │ Yes
         ▼
┌─────────────────┐
│ Check resume    │
│ preference      │
└────────┬────────┘
         │
    ┌────┴────┬────────────┐
    ▼         ▼            ▼
 Always    Always       Ask
Continue    New        (show
   │         │         dialog)
   ▼         ▼            │
 Resume    New            ▼
Session  Session    ┌──────────┐
                    │  User    │
                    │  Choice  │
                    └──────────┘
```
</startup-flow>

## Acceptance Criteria

<criteria>
- [ ] Startup detects recent sessions
- [ ] Resume dialog shows session preview
- [ ] [Y] continues the previous session
- [ ] [N] creates a new session
- [ ] [S] opens session selection list
- [ ] "Remember my choice" checkbox works
- [ ] Preference persists across restarts
- [ ] Gracefully handles deleted sessions
- [ ] Sessions older than 24 hours are not prompted
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test startup flow with various session states
4. Rename this file from `08-resume-continue-session.md` to `08-resume-continue-session.complete.md`
</completion>
