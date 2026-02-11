import XCTest
@testable import Smithers

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    func testInitialState_isHidden() {
        let wc = WindowCoordinator()
        XCTAssertFalse(wc.isWorkspacePanelVisible)
    }

    func testShow_setsVisibleTrue() {
        let wc = WindowCoordinator()
        wc.showWorkspacePanel()
        XCTAssertTrue(wc.isWorkspacePanelVisible)
    }

    func testShow_isIdempotent() {
        let wc = WindowCoordinator()
        wc.showWorkspacePanel()
        wc.showWorkspacePanel()
        XCTAssertTrue(wc.isWorkspacePanelVisible)
    }

    func testHide_setsVisibleFalse() {
        let wc = WindowCoordinator()
        wc.showWorkspacePanel()
        wc.hideWorkspacePanel()
        XCTAssertFalse(wc.isWorkspacePanelVisible)
    }

    func testHide_whenAlreadyHidden_remainsHidden() {
        let wc = WindowCoordinator()
        wc.hideWorkspacePanel()
        XCTAssertFalse(wc.isWorkspacePanelVisible)
    }
}
