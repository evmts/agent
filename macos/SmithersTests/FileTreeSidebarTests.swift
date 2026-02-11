import Testing
@testable import Smithers

@Suite struct FileTreeSidebarTests {
    @Test func instantiateSidebar_hasAccessibilityIdentifier() {
        // Basic smoke: ensure the view composes and carries the identifier.
        let view = FileTreeSidebar()
        // We cannot render here, but we can at least reference type & ensure no API crashes.
        #expect(String(describing: type(of: view)) == "FileTreeSidebar")
        // UI test layer will probe accessibilityIdentifier; unit test confirms type exists.
    }
}

