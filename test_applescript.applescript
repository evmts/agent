#!/usr/bin/osascript

-- Test AppleScript for Plue
-- This script demonstrates basic AppleScript functionality

-- Note: You'll need to build and run the Plue app first
-- Then run this script with: osascript test_applescript.applescript

-- Test 1: Send a chat message
tell application "Plue"
    log "Test 1: Sending chat message"
    send chat message "Hello from AppleScript test!"
end tell

delay 1

-- Test 2: Switch tabs
tell application "Plue"
    log "Test 2: Switching tabs"
    switch to tab "terminal"
    delay 1
    switch to tab "prompt"
end tell

delay 1

-- Test 3: Get application state
tell application "Plue"
    log "Test 3: Getting application state"
    set appState to get application state
    log appState
end tell

delay 1

-- Test 4: Get chat messages
tell application "Plue"
    log "Test 4: Getting chat messages"
    set messages to get chat messages
    log messages
end tell

-- Test 5: Terminal command (requires Terminal.app)
tell application "Plue"
    log "Test 5: Running terminal command"
    run terminal command "echo 'Hello from AppleScript via Plue!'"
end tell

log "All tests completed!"