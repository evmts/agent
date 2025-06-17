import XCTest

final class PlueUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // Test 1: Verifies that the app launches and the initial view is correct.
    func testAppLaunchAndInitialState() throws {
        // Assert that the Prompt tab is selected by default
        let promptTabButton = app.buttons[AccessibilityIdentifiers.tabButtonPrompt]
        XCTAssertTrue(promptTabButton.waitForExistence(timeout: 5), "Prompt tab button should exist on launch.")
        XCTAssertTrue(promptTabButton.isSelected, "Prompt tab should be selected by default.")

        // Assert that the welcome message is visible
        let welcomeTitle = app.staticTexts[AccessibilityIdentifiers.chatWelcomeTitle]
        XCTAssertTrue(welcomeTitle.exists, "The chat welcome title should be visible on launch.")
    }

    // Test 2: Verifies navigation between tabs.
    func testTabNavigation() throws {
        // Navigate to Agent tab
        let agentTabButton = app.buttons[AccessibilityIdentifiers.tabButtonAgent]
        XCTAssertTrue(agentTabButton.exists, "Agent tab button should exist.")
        agentTabButton.click()

        // Verify the Agent view is now visible
        let agentWelcomeTitle = app.staticTexts[AccessibilityIdentifiers.agentWelcomeTitle]
        XCTAssertTrue(agentWelcomeTitle.waitForExistence(timeout: 2), "Agent welcome title should appear after switching to the agent tab.")
        
        // Navigate to Farcaster tab
        let farcasterTabButton = app.buttons[AccessibilityIdentifiers.tabButtonFarcaster]
        XCTAssertTrue(farcasterTabButton.exists, "Farcaster tab button should exist.")
        farcasterTabButton.click()

        // Verify the "dev" channel exists in the sidebar
        let devChannel = app.buttons["\(AccessibilityIdentifiers.farcasterChannelPrefix)dev"]
        XCTAssertTrue(devChannel.waitForExistence(timeout: 2), "The 'dev' Farcaster channel should be visible.")
    }

    // Test 3: Verifies basic chat message sending.
    func testChatMessageSending() throws {
        let chatInputField = app.textFields[AccessibilityIdentifiers.chatInputField]
        XCTAssertTrue(chatInputField.exists, "Chat input field should exist.")

        let testMessage = "Hello, this is an E2E test!"
        chatInputField.click()
        chatInputField.typeText(testMessage)
        
        // Verify the send button is enabled and click it
        let sendButton = app.buttons[AccessibilityIdentifiers.chatSendButton]
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled after typing text.")
        sendButton.click()

        // Assert that the message appears in the chat history
        XCTAssertTrue(app.staticTexts[testMessage].waitForExistence(timeout: 2), "The sent message should appear in the chat view.")
    }
}