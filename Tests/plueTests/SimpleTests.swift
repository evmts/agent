import XCTest
@testable import plue

/// Simple tests that don't require FFI or singleton instances
class SimpleTests: XCTestCase {
    
    func testTabType() {
        XCTAssertEqual(TabType.prompt.rawValue, 0)
        XCTAssertEqual(TabType.farcaster.rawValue, 1)
        XCTAssertEqual(TabType.allCases.count, 8)
    }
    
    func testAppEventEnum() {
        let event1 = AppEvent.tabSwitched(.terminal)
        let event2 = AppEvent.terminalInput("test")
        let event3 = AppEvent.themeToggled
        
        // Just test that we can create events
        XCTAssertNotNil(event1)
        XCTAssertNotNil(event2)
        XCTAssertNotNil(event3)
    }
    
    func testAppStateInitial() {
        let state = AppState.initial
        XCTAssertEqual(state.currentTab, .prompt)
        XCTAssertTrue(state.isInitialized)
        XCTAssertNil(state.errorMessage)
    }
    
    func testPromptStateInitial() {
        let state = PromptState.initial
        XCTAssertEqual(state.conversations.count, 1)
        XCTAssertEqual(state.currentConversationIndex, 0)
        XCTAssertFalse(state.isProcessing)
    }
    
    func testTerminalStateInitial() {
        let state = TerminalState.initial
        XCTAssertFalse(state.isConnected)
        // Terminal buffer has some initial content
        XCTAssertFalse(state.buffer.isEmpty)
    }
    
    func testFarcasterStateInitial() {
        let state = FarcasterState.initial
        XCTAssertEqual(state.selectedChannel, "dev")
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.posts.count, 5) // Mock posts
    }
    
    func testVimStateInitial() {
        let state = VimState.initial
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(state.cursor.row, 0)
        XCTAssertEqual(state.cursor.col, 0)
    }
    
    func testMockPlueCore() {
        let mock = MockPlueCore()
        
        // Test initial state
        let state1 = mock.getCurrentState()
        XCTAssertEqual(state1.currentTab, .prompt)
        
        // Test subscription with expectation for async callback
        let expectation = XCTestExpectation(description: "State callback")
        mock.subscribe { state in
            // Initial state should still be prompt
            XCTAssertEqual(state.currentTab, .prompt)
            expectation.fulfill()
        }
        
        // Wait for the async callback
        wait(for: [expectation], timeout: 1.0)
        
        // Now test event handling
        mock.handleEvent(.tabSwitched(.agent))
        
        // Give it a moment to process
        Thread.sleep(forTimeInterval: 0.1)
        
        // Check that state changed
        let state2 = mock.getCurrentState()
        XCTAssertEqual(state2.currentTab, .agent)
    }
    
    func testDesignSystemTheme() {
        XCTAssertEqual(DesignSystem.Theme.dark.rawValue, "dark")
        XCTAssertEqual(DesignSystem.Theme.light.rawValue, "light")
    }
}