import XCTest
@testable import Smithers

final class ChatViewTests: XCTestCase {
    func testSidebarMode_allCases() {
        XCTAssertEqual(SidebarMode.allCases.count, 3)
        XCTAssertEqual(SidebarMode.chats.icon, "bubble.left.and.bubble.right")
        XCTAssertEqual(SidebarMode.source.icon, "arrow.triangle.branch")
        XCTAssertEqual(SidebarMode.agents.icon, "person.3")
    }
}
