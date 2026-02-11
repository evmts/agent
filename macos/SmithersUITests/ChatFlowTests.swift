import XCTest

final class ChatFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSendShowsAssistantBubble() {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textViews["composer_text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.click()
        composer.typeText("Hello")

        let send = app.buttons["composer_send"]
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        send.click()

        let assistant = app.staticTexts.matching(identifier: "bubble_assistant").firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: 3))
    }
}

