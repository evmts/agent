import XCTest

extension XCUIElement {
    /// Waits for the element to exist and then taps it
    func tapWhenReady(timeout: TimeInterval = 2) {
        XCTAssertTrue(self.waitForExistence(timeout: timeout), "Element \(self) should exist before tapping")
        self.tap()
    }
    
    /// Clears text field and types new text
    func clearAndTypeText(_ text: String) {
        guard self.elementType == .textField || self.elementType == .secureTextField else {
            XCTFail("clearAndTypeText can only be called on text fields")
            return
        }
        
        self.tap()
        
        // Select all text
        self.press(forDuration: 1.0)
        if let selectAll = self.menuItems["Select All"].waitForExistence(timeout: 1) ? self.menuItems["Select All"] : nil {
            selectAll.tap()
        }
        
        // Type new text (which will replace selection)
        self.typeText(text)
    }
}

extension XCTestCase {
    /// Takes a screenshot with a descriptive name
    func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    /// Waits for a condition to be true
    func waitFor(_ condition: @autoclosure @escaping () -> Bool, timeout: TimeInterval = 5, message: String = "Condition not met") {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            condition()
        }, object: nil)
        
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }
}