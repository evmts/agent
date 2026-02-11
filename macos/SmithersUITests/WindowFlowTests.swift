import XCTest

final class WindowFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOpenEditorFromChatTitleBarOpensIDE() {
        let app = XCUIApplication()
        app.launch()

        let openEditorButton = app.buttons["open_editor"]
        XCTAssertTrue(openEditorButton.waitForExistence(timeout: 3), "open_editor button not found")
        openEditorButton.click()

        let ideRoot = app.otherElements["ide_window_root"]
        XCTAssertTrue(ideRoot.waitForExistence(timeout: 3), "IDE window root not visible after tapping Open Editor")
    }
}

