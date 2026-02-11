import XCTest
@testable import Smithers

final class ChatViewTests: XCTestCase {
    func testSidebarMode_allCasesAndIcons() {
        // Verify enum surface contract (canonical 3 modes, correct icons/labels)
        XCTAssertEqual(SidebarMode.allCases.count, 3)

        XCTAssertEqual(SidebarMode.chats.icon, "bubble.left.and.bubble.right")
        XCTAssertEqual(SidebarMode.source.icon, "arrow.triangle.branch")
        XCTAssertEqual(SidebarMode.agents.icon, "person.3")

        XCTAssertEqual(SidebarMode.chats.label, "Chats")
        XCTAssertEqual(SidebarMode.source.label, "Source")
        XCTAssertEqual(SidebarMode.agents.label, "Agents")
    }
}
