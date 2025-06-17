import XCTest

final class PlueUITestsExtended: XCTestCase {
    
    private var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        takeScreenshot(named: "Test_End_State")
        app = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Extended Tab Navigation Tests
    
    func testAllTabsNavigation() throws {
        // Test navigation through all tabs
        let tabs: [(identifier: String, name: String)] = [
            (AccessibilityIdentifiers.tabButtonPrompt, "Prompt"),
            (AccessibilityIdentifiers.tabButtonFarcaster, "Farcaster"),
            (AccessibilityIdentifiers.tabButtonAgent, "Agent"),
            (AccessibilityIdentifiers.tabButtonTerminal, "Terminal"),
            (AccessibilityIdentifiers.tabButtonWeb, "Web"),
            (AccessibilityIdentifiers.tabButtonEditor, "Editor"),
            (AccessibilityIdentifiers.tabButtonDiff, "Diff"),
            (AccessibilityIdentifiers.tabButtonWorktree, "Worktree")
        ]
        
        for (identifier, name) in tabs {
            let tabButton = app.buttons[identifier]
            XCTAssertTrue(tabButton.exists, "\(name) tab button should exist")
            
            tabButton.click()
            takeScreenshot(named: "\(name)_Tab_View")
            
            // Give the view time to transition
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    // MARK: - Chat Interaction Tests
    
    func testChatMultipleMessages() throws {
        // Ensure we're on the Prompt tab
        app.buttons[AccessibilityIdentifiers.tabButtonPrompt].tapWhenReady()
        
        let messages = [
            "First test message",
            "Second test message with more content",
            "Third message 🚀"
        ]
        
        let chatInput = app.textFields[AccessibilityIdentifiers.chatInputField]
        let sendButton = app.buttons[AccessibilityIdentifiers.chatSendButton]
        
        for (index, message) in messages.enumerated() {
            chatInput.click()
            chatInput.typeText(message)
            
            XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled after typing")
            sendButton.click()
            
            // Verify message appears
            XCTAssertTrue(
                app.staticTexts[message].waitForExistence(timeout: 3),
                "Message '\(message)' should appear in chat"
            )
            
            takeScreenshot(named: "Chat_Message_\(index + 1)")
            
            // Wait for any response
            Thread.sleep(forTimeInterval: 1)
        }
    }
    
    func testChatInputFieldBehavior() throws {
        app.buttons[AccessibilityIdentifiers.tabButtonPrompt].tapWhenReady()
        
        let chatInput = app.textFields[AccessibilityIdentifiers.chatInputField]
        let sendButton = app.buttons[AccessibilityIdentifiers.chatSendButton]
        
        // Test empty state
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled when input is empty")
        
        // Test with spaces only
        chatInput.click()
        chatInput.typeText("   ")
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled with spaces")
        
        // Clear and test with actual content
        chatInput.clearAndTypeText("Test message")
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled with content")
    }
    
    // MARK: - Farcaster Tests
    
    func testFarcasterChannelNavigation() throws {
        app.buttons[AccessibilityIdentifiers.tabButtonFarcaster].tapWhenReady()
        
        // Wait for channels to load
        Thread.sleep(forTimeInterval: 1)
        
        // Test clicking on different channels
        let channels = ["dev", "design", "product"]
        
        for channel in channels {
            let channelButton = app.buttons["\(AccessibilityIdentifiers.farcasterChannelPrefix)\(channel)"]
            if channelButton.waitForExistence(timeout: 2) {
                channelButton.click()
                takeScreenshot(named: "Farcaster_Channel_\(channel)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    // MARK: - Agent View Tests
    
    func testAgentViewInitialState() throws {
        app.buttons[AccessibilityIdentifiers.tabButtonAgent].tapWhenReady()
        
        let agentWelcome = app.staticTexts[AccessibilityIdentifiers.agentWelcomeTitle]
        XCTAssertTrue(agentWelcome.waitForExistence(timeout: 2), "Agent welcome message should be visible")
        
        // Check for quick action buttons
        let quickActions = ["list worktrees", "start dagger", "create workflow", "help commands"]
        for action in quickActions {
            XCTAssertTrue(app.buttons[action].exists, "Quick action '\(action)' should exist")
        }
        
        takeScreenshot(named: "Agent_Initial_State")
    }
    
    // MARK: - Theme Toggle Tests
    
    func testThemeToggle() throws {
        // Find theme toggle button (could be in multiple places)
        let themeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'theme' OR label CONTAINS 'Toggle theme'"))
        
        if themeButtons.count > 0 {
            let initialScreenshot = app.screenshot()
            
            themeButtons.firstMatch.click()
            Thread.sleep(forTimeInterval: 0.5)
            
            let afterToggleScreenshot = app.screenshot()
            
            // Add screenshots to verify theme changed
            let attachment1 = XCTAttachment(screenshot: initialScreenshot)
            attachment1.name = "Theme_Before_Toggle"
            add(attachment1)
            
            let attachment2 = XCTAttachment(screenshot: afterToggleScreenshot)
            attachment2.name = "Theme_After_Toggle"
            add(attachment2)
        }
    }
    
    // MARK: - Keyboard Navigation Tests
    
    func testKeyboardShortcuts() throws {
        // Test tab switching with keyboard shortcuts
        app.typeKey("[", modifierFlags: .command) // Previous chat
        Thread.sleep(forTimeInterval: 0.3)
        
        app.typeKey("]", modifierFlags: .command) // Next chat
        Thread.sleep(forTimeInterval: 0.3)
        
        app.typeKey("n", modifierFlags: .command) // New chat/conversation
        Thread.sleep(forTimeInterval: 0.3)
        
        takeScreenshot(named: "After_Keyboard_Navigation")
    }
}