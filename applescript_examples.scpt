-- Plue AppleScript Examples
-- These examples demonstrate how to control Plue via AppleScript

-- Example 1: Run a terminal command
tell application "Plue"
    run terminal command "ls -la ~/Documents"
end tell

-- Example 2: Run a command in a new terminal tab
tell application "Plue"
    run terminal command "cd ~/Projects && git status" in new tab
end tell

-- Example 3: Send a chat message
tell application "Plue"
    send chat message "Hello from AppleScript! Can you help me with a coding task?"
end tell

-- Example 4: Get all chat messages
tell application "Plue"
    set allMessages to get chat messages
    display dialog allMessages
end tell

-- Example 5: Switch between tabs
tell application "Plue"
    switch to tab "terminal"
    delay 2
    switch to tab "chat"
end tell

-- Example 6: Open a file
tell application "Plue"
    open file "/Users/username/Documents/example.txt"
end tell

-- Example 7: Get application state
tell application "Plue"
    set appState to get application state
    display dialog appState
end tell

-- Example 8: Complex workflow - Run command and send results to chat
tell application "Plue"
    -- Run a command in terminal
    run terminal command "echo 'Hello from Terminal!'"
    
    -- Wait a moment for command to execute
    delay 1
    
    -- Get the terminal output
    set termOutput to get terminal output
    
    -- Send the output to chat
    send chat message "Terminal output: " & termOutput
end tell

-- Example 9: Save current file
tell application "Plue"
    save file
end tell

-- Example 10: Close terminal window
tell application "Plue"
    close terminal window
end tell

-- Example 11: Automated task runner
on runDailyTasks()
    tell application "Plue"
        -- Switch to terminal
        switch to tab "terminal"
        
        -- Run git pull
        run terminal command "cd ~/Projects/myproject && git pull"
        delay 2
        
        -- Run tests
        run terminal command "npm test" in new tab
        delay 5
        
        -- Get results and send to chat
        set testResults to get terminal output
        switch to tab "chat"
        send chat message "Daily test results: " & testResults
    end tell
end runDailyTasks

-- Call the function
runDailyTasks()